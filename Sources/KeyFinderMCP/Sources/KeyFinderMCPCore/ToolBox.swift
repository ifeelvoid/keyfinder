import Foundation
import KeyFinderEngine

/// Analyzes one file. Injected so tests run without real audio.
public protocol TrackAnalyzing: Sendable {
    func analyze(_ url: URL) async throws -> TrackSummary
}

/// Production analyzer: engine DSP (no CNN/Python) behind the on-disk cache.
public struct EngineAnalyzer: TrackAnalyzing {
    let cache: AnalysisCache

    public init(cache: AnalysisCache = AnalysisCache()) {
        self.cache = cache
    }

    public func analyze(_ url: URL) async throws -> TrackSummary {
        if let cached = cache.load(for: url) { return cached }
        let result = try await AudioProcessor().analyzeAudioFile(at: url)
        let summary = TrackSummary(result: result, path: url.path)
        cache.store(summary, for: url)
        return summary
    }
}

/// Implements the five tools. Every argument is validated here, at the boundary.
public struct ToolBox: Sendable {
    public static let maxFolderFiles = 500
    static let defaultFolderFiles = 200

    public struct Failure: Codable, Equatable, Sendable {
        public let path: String
        public let reason: String
    }

    let guardrail: PathGuard
    let analyzer: TrackAnalyzing
    let parallelism: Int
    /// When set, the allowed folders are re-read at each request, so changes made in the
    /// app's Settings apply without restarting the assistant.
    private let guardrailProvider: (@Sendable () -> PathGuard)?

    public init(guardrail: PathGuard, analyzer: TrackAnalyzing,
                parallelism: Int = ToolBox.defaultParallelism) {
        self.guardrail = guardrail
        self.analyzer = analyzer
        self.parallelism = parallelism
        self.guardrailProvider = nil
    }

    public init(guardrailProvider: @escaping @Sendable () -> PathGuard, analyzer: TrackAnalyzing,
                parallelism: Int = ToolBox.defaultParallelism) {
        self.guardrail = guardrailProvider()
        self.analyzer = analyzer
        self.parallelism = parallelism
        self.guardrailProvider = guardrailProvider
    }

    public static var defaultParallelism: Int {
        max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    /// A copy pinned to the folders allowed right now.
    private func current() -> ToolBox {
        guard let provider = guardrailProvider else { return self }
        return ToolBox(guardrail: provider(), analyzer: analyzer, parallelism: parallelism)
    }

    public var definitions: [JSONValue] {
        ToolDefinitions.all(rootsDescription: current().guardrail.rootsDescription)
    }

    public func call(_ name: String, arguments: JSONValue) async throws -> JSONValue {
        guard guardrailProvider == nil else { return try await current().call(name, arguments: arguments) }
        let args = Arguments(arguments)
        switch name {
        case "analyze_track": return try await analyzeTrack(args)
        case "analyze_folder": return try await analyzeFolder(args)
        case "find_compatible": return try await findCompatible(args)
        case "build_set": return try await buildSet(args)
        case "fit_sample": return try await fitSample(args)
        default: throw ToolError.invalidArgument("Unknown tool: \(name)")
        }
    }

    // MARK: - Tools

    private func analyzeTrack(_ args: Arguments) async throws -> JSONValue {
        let url = try guardrail.audioFile(try args.string("path"))
        return try JSONValue.from(try await analyze(url))
    }

    private func analyzeFolder(_ args: Arguments) async throws -> JSONValue {
        let limit = try args.boundedInt("limit", default: ToolBox.defaultFolderFiles, range: 1...ToolBox.maxFolderFiles)
        let library = try await loadFolder(args, pathKey: "path", fileLimit: limit)
        return try JSONValue.from(library)
    }

    private func findCompatible(_ args: Arguments) async throws -> JSONValue {
        let reference: (camelot: CamelotKey, bpm: Double, energy: Int?, path: String?)
        if let trackPath = try args.optionalString("track_path") {
            let track = try await analyze(try guardrail.audioFile(trackPath))
            guard let key = track.camelotKey else { throw ToolError.analysisFailed("No key detected for \(track.fileName).") }
            reference = (key, track.bpm, track.energyRank, track.path)
        } else {
            guard let camelot = try args.optionalString("camelot"), let bpm = try args.optionalDouble("bpm") else {
                throw ToolError.invalidArgument("Give either track_path, or camelot plus bpm.")
            }
            reference = (try Arguments.camelot(camelot), try Arguments.positiveBPM(bpm), nil, nil)
        }
        let tolerance = try args.optionalDouble("bpm_tolerance") ?? 6
        guard (0...50).contains(tolerance) else { throw ToolError.invalidArgument("bpm_tolerance must be 0-50.") }
        let limit = try args.boundedInt("limit", default: 25, range: 1...200)

        let library = try await loadFolder(args, pathKey: "folder", fileLimit: ToolBox.defaultFolderFiles)
        let matches = HarmonicMixer.compatible(with: reference.camelot, bpm: reference.bpm, energyRank: reference.energy,
                                               excludingPath: reference.path, in: library.analyzed,
                                               bpmTolerance: tolerance)
        return try JSONValue.from(CompatibleResult(
            reference: .init(camelot: reference.camelot.description, bpm: reference.bpm, path: reference.path),
            matches: Array(matches.prefix(limit)), searched: library.analyzed.count,
            failed: library.failed, truncated: library.truncated))
    }

    private func buildSet(_ args: Arguments) async throws -> JSONValue {
        let shapeName = try args.optionalString("energy_shape") ?? "build"
        guard let shape = HarmonicMixer.EnergyShape(rawValue: shapeName) else {
            throw ToolError.invalidArgument("energy_shape must be build, flat or peak.")
        }
        let library = try await loadFolder(args, pathKey: "folder", fileLimit: ToolBox.defaultFolderFiles)
        guard !library.analyzed.isEmpty else { throw ToolError.notFound("No analyzable audio in that folder.") }

        var start: TrackSummary?
        if let startPath = try args.optionalString("start_path") {
            let url = try guardrail.audioFile(startPath)
            start = library.analyzed.first { $0.path == url.path }
            guard start != nil else { throw ToolError.invalidArgument("start_path must be one of the analyzed tracks in the folder.") }
        }

        var maxTracks = try args.boundedInt("max_tracks", default: 20, range: 1...ToolBox.maxFolderFiles)
        if let minutes = try args.optionalDouble("target_minutes") {
            guard (1...720).contains(minutes) else { throw ToolError.invalidArgument("target_minutes must be 1-720.") }
            let average = library.analyzed.map(\.duration).reduce(0, +) / Double(library.analyzed.count)
            maxTracks = max(1, Int((minutes * 60 / max(average, 60)).rounded(.up)))
        }

        let set = HarmonicMixer.buildSet(from: library.analyzed, start: start, maxTracks: maxTracks, shape: shape)
        let minutes = (set.map(\.track.duration).reduce(0, +) / 60 * 10).rounded() / 10
        return try JSONValue.from(SetResult(energyShape: shape.rawValue, totalMinutes: minutes, set: set,
                                            failed: library.failed, truncated: library.truncated))
    }

    private func fitSample(_ args: Arguments) async throws -> JSONValue {
        let url = try guardrail.audioFile(try args.string("sample_path"))
        let targetKey = try Arguments.camelot(try args.string("target_camelot"))
        let targetBPM = try Arguments.positiveBPM(try args.double("target_bpm"))
        let keyOverride = try args.optionalString("sample_camelot").map(Arguments.camelot)
        let bpmOverride = try args.optionalDouble("sample_bpm").map(Arguments.positiveBPM)

        let detected: TrackSummary? = (keyOverride != nil && bpmOverride != nil) ? nil : try await analyze(url)
        guard let sampleKey = keyOverride ?? detected?.camelotKey else {
            throw ToolError.analysisFailed("No key detected for \(url.lastPathComponent); pass sample_camelot.")
        }
        let sampleBPM = bpmOverride ?? detected?.bpm ?? 0
        guard sampleBPM > 0 else { throw ToolError.analysisFailed("No tempo detected; pass sample_bpm.") }

        let fit = SampleFit.compute(sampleKey: sampleKey, sampleBPM: sampleBPM, targetKey: targetKey, targetBPM: targetBPM)
        return try JSONValue.from(FitResult(sample: .init(path: url.path, camelot: sampleKey.description, bpm: sampleBPM,
                                                         keySource: keyOverride == nil ? "detected" : "given",
                                                         bpmSource: bpmOverride == nil ? "detected" : "given"),
                                            target: .init(camelot: targetKey.description, bpm: targetBPM),
                                            fit: fit))
    }

    // MARK: - Analysis

    struct FolderResult: Codable, Sendable {
        let folder: String
        let analyzed: [TrackSummary]
        let failed: [Failure]
        let truncated: Bool
    }

    private func loadFolder(_ args: Arguments, pathKey: String, fileLimit: Int) async throws -> FolderResult {
        let folder = try guardrail.folder(try args.string(pathKey))
        let recursive = try args.optionalBool("recursive") ?? true
        let listing = guardrail.audioFiles(in: folder, recursive: recursive, limit: fileLimit)
        let (analyzed, failed) = await analyzeMany(listing.files)
        return FolderResult(folder: folder.path, analyzed: analyzed, failed: failed, truncated: listing.truncated)
    }

    private func analyze(_ url: URL) async throws -> TrackSummary {
        do {
            return try await analyzer.analyze(url)
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.analysisFailed("Could not analyze \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Analyzes with bounded parallelism; results come back in input order.
    func analyzeMany(_ urls: [URL]) async -> ([TrackSummary], [Failure]) {
        let analyzer = self.analyzer
        var results = [Result<TrackSummary, Error>?](repeating: nil, count: urls.count)
        @Sendable func run(_ index: Int) async -> (Int, Result<TrackSummary, Error>) {
            do { return (index, .success(try await analyzer.analyze(urls[index]))) }
            catch { return (index, .failure(error)) }
        }
        // Explicit index iterator and group.next(): a nested enqueue() that captured the
        // group and a mutable counter misfiled results under real (slow) analysis.
        await withTaskGroup(of: (Int, Result<TrackSummary, Error>).self) { group in
            var pending = urls.indices.makeIterator()
            for _ in 0..<parallelism {
                guard let index = pending.next() else { break }
                group.addTask { await run(index) }
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if let nextIndex = pending.next() {
                    group.addTask { await run(nextIndex) }
                }
            }
        }
        var analyzed: [TrackSummary] = []
        var failed: [Failure] = []
        for (url, result) in zip(urls, results) {
            switch result {
            case .success(let summary): analyzed.append(summary)
            case .failure(let error): failed.append(Failure(path: url.path, reason: error.localizedDescription))
            case nil: failed.append(Failure(path: url.path, reason: "Not analyzed."))
            }
        }
        return (analyzed, failed)
    }
}

// MARK: - Result shapes

struct CompatibleResult: Codable {
    struct Reference: Codable { let camelot: String; let bpm: Double; let path: String? }
    let reference: Reference
    let matches: [HarmonicMixer.Match]
    let searched: Int
    let failed: [ToolBox.Failure]
    let truncated: Bool
}

struct SetResult: Codable {
    let energyShape: String
    let totalMinutes: Double
    let set: [HarmonicMixer.SetEntry]
    let failed: [ToolBox.Failure]
    let truncated: Bool
}

struct FitResult: Codable {
    struct Sample: Codable { let path: String; let camelot: String; let bpm: Double; let keySource: String; let bpmSource: String }
    struct Target: Codable { let camelot: String; let bpm: Double }
    let sample: Sample
    let target: Target
    let fit: SampleFit
}
