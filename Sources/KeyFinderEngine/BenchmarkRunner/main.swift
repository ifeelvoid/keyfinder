import Foundation
import CryptoKit
import KeyFinderEngine
import Darwin

// All generated artifacts belong outside the read-only catalog, normally under dist/.
struct Candidate: Codable {
    let id: String
    let relativePath: String
    let alternatives: [String]
    let provisionalKey: String?
    let provisionalBPM: Double?
    let labelNote: String
}
struct Manifest: Codable {
    let schemaVersion: Int
    let root: String
    let createdAt: String
    let audioFileCount: Int
    let excluded: [String]
    let candidates: [Candidate]
}
struct Measurement: Codable {
    let id: String
    let relativePath: String
    let audioSHA256: String?
    let sourceUnchanged: Bool
    let key: String?
    let camelot: String?
    let bpm: Double?
    let heuristicConfidence: Double?
    let duration: Double?
    let elapsedSeconds: Double
    let error: String?
    let tonalEvidence: [KeyDetector.TonalSegment]?
}
struct RunInfo: Codable {
    let startedAt: String
    let engineSHA256: String
    let executableSHA256: String
    let manifestSHA256: String
    let selectedIDs: [String]
    let warning: String
    // Absent in older runs, which always used full audio analysis.
    let analysisMode: String?
}
struct ReferenceMeasurement: Codable {
    let id: String
    let audioSHA256: String
    let camelot: String?
    let seconds: Double
    let error: String?
}
struct ReferenceInfo: Codable {
    let createdAt: String
    let binarySHA256: String
    let manifestSHA256: String
    let ourResultsSHA256: String
    let toolPath: String
}

enum BenchmarkError: Error { case invalid(String) }
let fm = FileManager.default
let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}()
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func fileDigest(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func write<T: Encodable>(_ value: T, to url: URL) throws {
    try encoder.encode(value).write(to: url, options: .atomic)
}
func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw BenchmarkError.invalid(message) }
}
func outsideCatalog(_ output: URL, root: URL) throws {
    let destination = output.resolvingSymlinksInPath().standardizedFileURL.path
    let catalog = root.resolvingSymlinksInPath().standardizedFileURL.path
    try check(destination != catalog && !destination.hasPrefix(catalog + "/"), "Output must be outside the catalog")
}
func label(_ filename: String) -> (String?, Double?, String) {
    let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    let clean = stem.components(separatedBy: " [").first ?? stem
    // Anchored suffix only: never interpret a note in the song title as its key.
    let pattern = #"(?:^|\s)(\d{2,3}(?:\.\d+)?)\s+([A-G])([#b]?)(m|M|maj|major|min|minor)?$"#
    let expression = try! NSRegularExpression(pattern: pattern)
    if let match = expression.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
        let ns = clean as NSString
        let bpm = Double(ns.substring(with: match.range(at: 1)))
        let note = ns.substring(with: match.range(at: 2)) + ns.substring(with: match.range(at: 3))
        let mode = match.range(at: 4).location == NSNotFound ? "" : ns.substring(with: match.range(at: 4))
        if mode == "M" { return (nil, bpm, "Provisional; uppercase M mode is ambiguous; confirm manually") }
        let enharmonics = ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#", "Cb": "B", "Fb": "E", "B#": "C", "E#": "F"]
        let key = (enharmonics[note] ?? note) + (["m", "min", "minor"].contains(mode) ? " Minor" : " Major")
        return (key, bpm, "Provisional filename estimate; mixed human/detector provenance")
    }
    let tempo = try! NSRegularExpression(pattern: #"(?:^|\s)(\d{2,3}(?:\.\d+)?)$"#)
    if let match = tempo.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
        return (nil, Double((clean as NSString).substring(with: match.range(at: 1))), "Provisional tempo only; key missing")
    }
    return (nil, nil, "No parseable filename reference")
}
let formatRank = ["wav": 0, "aiff": 1, "aif": 2, "flac": 3, "m4a": 4, "mp3": 5, "aac": 6]
func choose(_ paths: [String]) -> [String] {
    paths.sorted {
        let a = formatRank[URL(fileURLWithPath: $0).pathExtension.lowercased()] ?? 99
        let b = formatRank[URL(fileURLWithPath: $1).pathExtension.lowercased()] ?? 99
        return a == b ? $0 < $1 : a < b
    }
}
func inventory(root inputRoot: URL) throws -> Manifest {
    let root = inputRoot.resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    try check(fm.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue,
              "Catalog root is not a directory")
    var groups: [String: [String]] = [:]
    var excluded: [String] = []
    var total = 0
    var enumerationError: Error?
    guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                    options: [.skipsHiddenFiles], errorHandler: { _, error in
        enumerationError = error; return false
    }) else { throw BenchmarkError.invalid("Cannot enumerate catalog") }
    for case let url as URL in walker {
        guard formatRank[url.pathExtension.lowercased()] != nil else { continue }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        // Enumeration may expand /var to /private/var even after root canonicalization.
        // Resolve the parent alias, preserving the entry name and symlink metadata.
        let entryPath = url.deletingLastPathComponent().resolvingSymlinksInPath()
            .standardizedFileURL.appendingPathComponent(url.lastPathComponent).path
        try check(entryPath.hasPrefix(root.path + "/"), "Inventory entry escapes catalog")
        let relative = String(entryPath.dropFirst(root.path.count + 1))
        total += 1
        let folders = url.deletingLastPathComponent().pathComponents.map { $0.lowercased() }
        let stemFolder = folders.contains { ["stems", "trackouts", "track outs", "trackout", "stems & midi"].contains($0) }
        guard values.isRegularFile == true, values.isSymbolicLink != true, !stemFolder else {
            excluded.append(relative); continue
        }
        let group = (relative as NSString).deletingPathExtension
        groups[group, default: []].append(relative)
    }
    if let error = enumerationError { throw error }
    let candidates = groups.values.map { paths -> Candidate in
        let ranked = choose(paths)
        let primary = ranked[0]
        let reference = label(primary)
        return Candidate(id: digest(Data(primary.utf8)), relativePath: primary,
                         alternatives: Array(ranked.dropFirst()), provisionalKey: reference.0,
                         provisionalBPM: reference.1, labelNote: reference.2)
    }.sorted { $0.id < $1.id } // Stable dispersed pilot, not the first alphabetical genre.
    return Manifest(schemaVersion: 1, root: root.path, createdAt: ISO8601DateFormatter().string(from: Date()),
                    audioFileCount: total, excluded: excluded.sorted(), candidates: candidates)
}
func engineDigest(_ root: URL) throws -> String {
    let source = root.appendingPathComponent("Sources/KeyFinderEngine")
    guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: nil) else {
        throw BenchmarkError.invalid("Engine source directory missing")
    }
    let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
    try check(!files.isEmpty, "Engine source files missing")
    var data = Data()
    for file in files {
        data.append(Data(file.lastPathComponent.utf8)); data.append(0)
        data.append(try Data(contentsOf: file)); data.append(0)
    }
    return digest(data)
}
func report(_ measurements: [Measurement], manifest: Manifest, directory: URL) throws {
    let lookup = Dictionary(uniqueKeysWithValues: manifest.candidates.map { ($0.id, $0) })
    var keyCount = 0, keyMatches = 0, tempoCount = 0, tempoMatches = 0, octave = 0
    var queue = [["id", "file", "provisional_key", "detected_key", "provisional_bpm", "detected_bpm", "review_reason", "verified_key", "verified_bpm", "evidence"]]
    for measurement in measurements {
        guard let candidate = lookup[measurement.id] else { continue }
        var reasons: [String] = []
        if let error = measurement.error { reasons.append("ERROR: " + error) }
        if !measurement.sourceUnchanged { reasons.append("Source integrity not confirmed") }
        if let reference = candidate.provisionalKey, let key = measurement.key {
            keyCount += 1
            if reference == key { keyMatches += 1 } else { reasons.append("Key disagreement") }
        } else { reasons.append("Key reference missing or ambiguous") }
        if let reference = candidate.provisionalBPM, let bpm = measurement.bpm {
            tempoCount += 1
            if abs(reference - bpm) <= 0.01 * reference { tempoMatches += 1 }
            else if min(abs(bpm * 2 - reference), abs(bpm / 2 - reference)) <= 0.01 * reference {
                octave += 1; reasons.append("Half/double tempo disagreement")
            } else { reasons.append("Tempo disagreement") }
        }
        if (measurement.heuristicConfidence ?? 0) >= 0.9 && reasons.contains("Key disagreement") {
            reasons.append("High heuristic confidence despite disagreement")
        }
        if reasons.isEmpty && Int(candidate.id.prefix(2), radix: 16)! % 5 == 0 {
            reasons.append("Deterministic agreement audit sample")
        }
        if !reasons.isEmpty {
            queue.append([candidate.id, candidate.relativePath, candidate.provisionalKey ?? "", measurement.key ?? "",
                          candidate.provisionalBPM.map { String($0) } ?? "", measurement.bpm.map { String($0) } ?? "",
                          reasons.joined(separator: "; "), "", "", ""])
        }
    }
    try DJExport.csv(queue).write(to: directory.appendingPathComponent("review-queue.csv"), atomically: true, encoding: .utf8)
    let failures = measurements.filter { $0.error != nil }.count
    let text = """
    # Catalog detector baseline

    PROVISIONAL LABEL AGREEMENT ONLY — NOT MEASURED ACCURACY.
    No independent detector results or verified reference labels have been collected.

    - Catalog audio files: \(manifest.audioFileCount)
    - Candidate masters after exact basename/format grouping: \(manifest.candidates.count)
    - Excluded stem/symlink/nonregular paths: \(manifest.excluded.count)
    - Analyzed: \(measurements.count); successful: \(measurements.count - failures); failures: \(failures)
    - Exact filename-key agreement: \(keyMatches)/\(keyCount) comparable successful results
    - Filename-tempo agreement within 1%: \(tempoMatches)/\(tempoCount) comparable successful results
    - Additional half/double-tempo matches: \(octave) (not counted as exact)
    - Review queue: \(queue.count - 1) rows
    - Analysis wall seconds (sum): \(Int(measurements.reduce(0) { $0 + $1.elapsedSeconds }))

    Filename labels have mixed provenance. Numbered versions, remasters and duplicate
    song families still require review; candidate masters are not a unique-song count.
    This development set is NOT an untouched final test set. Do not tune the detector
    using these results and then present them as held-out accuracy.

    Raw measurements are in results.json; exact source/executable/manifest fingerprints
    and requested IDs are in run.json. All source audio was opened read-only.
    """
    try text.write(to: directory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
}
func selfTest() throws {
    try check(label("Beat 90 Dm [Prod. IFEELVOID].wav").0 == "D Minor", "Minor parsing")
    try check(label("Beat 120 Db.wav").0 == "C# Major", "Enharmonic parsing")
    try check(label("Beat 161 GM.wav").0 == nil, "Uppercase M needs adjudication")
    try check(label("Beat 90.wav").1 == 90, "Tempo-only parsing")
    try check(label("C Major Story.wav").0 == nil, "No title-derived reference")
    try check(choose(["a.mp3", "a.wav", "a.m4a"]).first == "a.wav", "Lossless preference")
    try check(label("Beat 90 Dm [Prod. IFEELVOID] 2.mp3").0 == "D Minor", "Version suffix handling")
    do { try outsideCatalog(URL(fileURLWithPath: "/tmp/catalog/out"), root: URL(fileURLWithPath: "/tmp/catalog")); throw BenchmarkError.invalid("Unsafe output accepted") }
    catch BenchmarkError.invalid(let message) { try check(message == "Output must be outside the catalog", "Output containment") }
    let temporary = fm.temporaryDirectory.appendingPathComponent("KeyFinderBenchmarkTest-\(UUID())")
    try fm.createDirectory(at: temporary.appendingPathComponent("stems"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temporary) }
    for file in ["Beat 90 Dm.wav", "Beat 90 Dm.mp3", "Beat 90 Dm 2.mp3", "stems/kick.wav"] {
        try Data([1, 2, 3]).write(to: temporary.appendingPathComponent(file), options: .withoutOverwriting)
    }
    let manifest = try inventory(root: temporary)
    try check(manifest.audioFileCount == 4 && manifest.candidates.count == 2 && manifest.excluded.count == 1,
              "Inventory preserves versions, groups formats and excludes stems")
    try check(manifest.candidates.contains { $0.relativePath == "Beat 90 Dm.wav" && $0.alternatives == ["Beat 90 Dm.mp3"] },
              "WAV is selected, MP3 remains recorded")
    let bytes = try encoder.encode(manifest)
    let decoded = try JSONDecoder().decode(Manifest.self, from: bytes)
    try check(decoded.candidates.map(\.id) == manifest.candidates.map(\.id), "Manifest round trip")
    try check(try fileDigest(temporary.appendingPathComponent("Beat 90 Dm.wav")) == digest(Data([1, 2, 3])), "Streaming SHA-256")
    let legacyRun = Data(#"{"startedAt":"legacy","engineSHA256":"engine","executableSHA256":"executable","manifestSHA256":"manifest","selectedIDs":[],"warning":"provisional"}"#.utf8)
    let legacyInfo = try JSONDecoder().decode(RunInfo.self, from: legacyRun)
    try check(legacyInfo.analysisMode == nil, "Legacy run metadata remains decodable")
    let keyOnlyInfo = RunInfo(startedAt: "test", engineSHA256: "engine", executableSHA256: "executable",
        manifestSHA256: "manifest", selectedIDs: [], warning: "provisional", analysisMode: "key-only")
    let decodedInfo = try JSONDecoder().decode(RunInfo.self, from: encoder.encode(keyOnlyInfo))
    try check(decodedInfo.analysisMode == "key-only", "Key-only analysis mode round trip")
    let legacyMeasurement = Data(#"{"id":"test","relativePath":"test.wav","sourceUnchanged":true,"elapsedSeconds":0}"#.utf8)
    let decodedMeasurement = try JSONDecoder().decode(Measurement.self, from: legacyMeasurement)
    try check(decodedMeasurement.tonalEvidence == nil, "Legacy measurement remains decodable without tonal evidence")
    print("PASS: benchmark labels, grouping, exclusions, version preservation, manifest round trip, hashing and output containment")
}

@MainActor
func compare(manifestURL: URL, resultsURL: URL, output: URL, executable: URL) async throws {
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
    try check(manifest.schemaVersion == 1 && Set(manifest.candidates.map(\.id)).count == manifest.candidates.count,
              "Unsupported or duplicate manifest entries")
    let ownData = try Data(contentsOf: resultsURL)
    let ours = try JSONDecoder().decode([Measurement].self, from: ownData)
    let root = URL(fileURLWithPath: manifest.root).resolvingSymlinksInPath().standardizedFileURL
    try outsideCatalog(output, root: root)
    try check(!fm.fileExists(atPath: output.path), "Use a fresh reference output directory")
    try check(Set(ours.map(\.id)).count == ours.count, "Duplicate measurement IDs")
    let candidates = Dictionary(uniqueKeysWithValues: manifest.candidates.map { ($0.id, $0) })
    try fm.createDirectory(at: output, withIntermediateDirectories: true)
    let info = ReferenceInfo(createdAt: ISO8601DateFormatter().string(from: Date()),
        binarySHA256: try fileDigest(executable), manifestSHA256: digest(manifestData),
        ourResultsSHA256: digest(ownData), toolPath: executable.path)
    try write(info, to: output.appendingPathComponent("reference-run.json"))
    var references: [ReferenceMeasurement] = []
    for own in ours {
        guard let candidate = candidates[own.id] else { throw BenchmarkError.invalid("Measurement not in manifest") }
        let file = root.appendingPathComponent(candidate.relativePath).resolvingSymlinksInPath().standardizedFileURL
        try check(file.path.hasPrefix(root.path + "/"), "Reference input outside catalog")
        let before = try fileDigest(file)
        try check(before == own.audioSHA256 && own.sourceUnchanged, "Reference audio differs from baseline audio")
        let stdoutURL = output.appendingPathComponent(own.id + ".stdout.txt")
        let stderrURL = output.appendingPathComponent(own.id + ".stderr.txt")
        try Data().write(to: stdoutURL, options: .withoutOverwriting)
        try Data().write(to: stderrURL, options: .withoutOverwriting)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-n", "camelot", file.path]
        process.standardOutput = stdout
        process.standardError = stderr
        let started = Date()
        try process.run()
        while process.isRunning && Date().timeIntervalSince(started) < 120 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            for _ in 0..<50 where process.isRunning { try await Task.sleep(nanoseconds: 100_000_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try stdout.synchronize(); try stderr.synchronize()
        try check(try fileDigest(file) == before, "Reference run changed source audio")
        let raw = try String(contentsOf: stdoutURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = KeyDetector.MusicalKey.allCases.contains { $0.camelotNotation == raw }
        let error: String? = timedOut ? "Reference timeout (120s)" : process.terminationStatus != 0 ? "Reference exit \(process.terminationStatus); see stderr" : !valid ? "No valid key returned" : nil
        references.append(ReferenceMeasurement(id: own.id, audioSHA256: before, camelot: error == nil ? raw : nil,
                                               seconds: Date().timeIntervalSince(started), error: error))
        try write(references, to: output.appendingPathComponent("reference-results.json"))
        print("REFERENCE \(references.count)/\(ours.count): \(candidate.relativePath)")
    }
    var table = [["id", "file", "provisional_filename_key", "our_key", "reference_key", "engines_agree", "review_reason", "verified_key", "evidence"]]
    var agreements = 0, comparable = 0, ownLabelMatches = 0, refLabelMatches = 0, labelCount = 0
    for reference in references {
        let own = ours.first { $0.id == reference.id }!
        let candidate = candidates[reference.id]!
        let referenceKey = KeyDetector.MusicalKey.allCases.first { $0.camelotNotation == reference.camelot }?.rawValue
        let agree = reference.camelot != nil && own.camelot != nil && reference.camelot == own.camelot
        if reference.camelot != nil && own.camelot != nil {
            comparable += 1; if agree { agreements += 1 }
            if let provisional = candidate.provisionalKey {
                labelCount += 1
                if provisional == own.key { ownLabelMatches += 1 }
                if provisional == referenceKey { refLabelMatches += 1 }
            }
        }
        table.append([own.id, candidate.relativePath, candidate.provisionalKey ?? "", own.key ?? "", referenceKey ?? "",
                      agree ? "yes" : "no", reference.error ?? own.error ?? (agree ? "Agreement still needs a human audit" : "Independent detectors disagree"), "", ""])
    }
    try DJExport.csv(table).write(to: output.appendingPathComponent("comparison.csv"), atomically: true, encoding: .utf8)
    let summary = """
    # Independent KeyFinder comparison

    Agreement is NOT accuracy. Filename labels have mixed unverified provenance.

    - Files attempted: \(references.count)
    - Engines agree on exact tonic/mode: \(agreements)/\(comparable) comparable results
    - Against provisional filename labels on the same comparable subset (\(labelCount) files):
      - Our detector: \(ownLabelMatches)/\(labelCount)
      - Original KeyFinder algorithm: \(refLabelMatches)/\(labelCount)
    - Reference errors/abstentions: \(references.filter { $0.error != nil }.count)

    The reference is standalone libkeyfinder through keyfinder-cli, not the original
    legacy macOS GUI. Audio SHA-256 verified before/after both runs. Compare identical
    inputs, then adjudicate with project notes/chords. Neither detector is ground truth.
    All rows, including agreements, are available in comparison.csv for review.
    Tunebat has not been run. No engine changes were made during this baseline.
    """
    try summary.write(to: output.appendingPathComponent("comparison.md"), atomically: true, encoding: .utf8)
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw BenchmarkError.invalid("Use inventory ROOT MANIFEST | analyze MANIFEST NEW_OUTPUT_DIR ENGINE_PACKAGE [LIMIT] | analyze-key MANIFEST NEW_OUTPUT_DIR ENGINE_PACKAGE [LIMIT] | analyze-features MANIFEST NEW_OUTPUT_DIR ENGINE_PACKAGE [LIMIT] | compare MANIFEST OUR_RESULTS NEW_OUTPUT_DIR REFERENCE_CLI | self-test") }
    if command == "self-test" { try selfTest() }
    else if command == "inventory", args.count == 3 {
        let root = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath().standardizedFileURL
        let destination = URL(fileURLWithPath: args[2])
        try outsideCatalog(destination, root: root)
        try check(!fm.fileExists(atPath: destination.path), "Manifest already exists; use a fresh path")
        let manifest = try inventory(root: root)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(manifest, to: destination)
        print("Inventoried \(manifest.audioFileCount) audio files; \(manifest.candidates.count) candidates; \(manifest.excluded.count) excluded")
    } else if ["analyze", "analyze-key", "analyze-features"].contains(command), (4...5).contains(args.count) {
        let exportFeatures = command == "analyze-features"
        let modeName = ProcessInfo.processInfo.environment["KEYFINDER_SPECTRAL_MODE"] ?? "baseline"
        guard let spectralMode = KeyDetector.SpectralMode(rawValue: modeName) else {
            throw BenchmarkError.invalid("KEYFINDER_SPECTRAL_MODE must be one of \(KeyDetector.SpectralMode.allCases.map(\.rawValue))")
        }
        let environment = ProcessInfo.processInfo.environment
        guard let keyStyle = KeyStyle(rawValue: environment["KEYFINDER_KEY_STYLE"] ?? "edm"),
              let keyMethod = KeyMethod(rawValue: environment["KEYFINDER_KEY_METHOD"] ?? "templates") else {
            throw BenchmarkError.invalid("KEYFINDER_KEY_STYLE must be edm|trapHipHop; KEYFINDER_KEY_METHOD templates|model")
        }
        let modeSuffix = (spectralMode == .baseline ? "" : "+\(spectralMode.rawValue)")
            + (keyStyle == .edm ? "" : "+\(keyStyle.rawValue)") + (keyMethod == .templates ? "" : "+\(keyMethod.rawValue)")
        let makeDetector = { KeyDetector(spectralMode: spectralMode, style: keyStyle, method: keyMethod) }
        // Optional label-scope truncation (e.g. FMAK labels describe the first 60 s); recorded in run.json.
        let maxSeconds = environment["KEYFINDER_MAX_SECONDS"].flatMap(Double.init)
        if let maxSeconds { try check(maxSeconds.isFinite && maxSeconds >= 1, "KEYFINDER_MAX_SECONDS must be >= 1") }
        let scopeSuffix = maxSeconds.map { "+first\(Int($0))s" } ?? ""
        let keyOnly = command != "analyze"
        let manifestURL = URL(fileURLWithPath: args[1])
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        try check(manifest.schemaVersion == 1 && Set(manifest.candidates.map(\.id)).count == manifest.candidates.count,
                  "Unsupported or duplicate manifest entries")
        let root = URL(fileURLWithPath: manifest.root).resolvingSymlinksInPath().standardizedFileURL
        let output = URL(fileURLWithPath: args[2])
        try outsideCatalog(output, root: root)
        try check(!fm.fileExists(atPath: output.path), "Use a fresh output directory; previous evidence is preserved")
        let limit = args.count == 5 ? Int(args[4]) : manifest.candidates.count
        guard let limit, limit > 0 else { throw BenchmarkError.invalid("LIMIT must be a positive integer") }
        let selected = Array(manifest.candidates.prefix(limit))
        try check(!selected.isEmpty, "No candidates")
        let sourceHash = try engineDigest(URL(fileURLWithPath: args[3]))
        let info = RunInfo(startedAt: ISO8601DateFormatter().string(from: Date()), engineSHA256: sourceHash,
                           executableSHA256: try fileDigest(URL(fileURLWithPath: CommandLine.arguments[0])),
                           manifestSHA256: digest(manifestData), selectedIDs: selected.map(\.id),
                           warning: "Filename labels are provisional. Baseline agreement is not accuracy.",
                           analysisMode: (exportFeatures ? "tonal-features" : keyOnly ? "key-only" : "full") + modeSuffix + scopeSuffix)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        try write(info, to: output.appendingPathComponent("run.json"))
        var results: [Measurement] = []
        for candidate in selected {
            let started = Date()
            let file = root.appendingPathComponent(candidate.relativePath).resolvingSymlinksInPath().standardizedFileURL
            var before: String?
            var unchanged = false
            do {
                try check(file.path.hasPrefix(root.path + "/"), "Manifest path escapes catalog")
                before = try fileDigest(file)
                let key: KeyDetector.MusicalKey
                let confidence: Double
                let duration: Double
                let bpm: Double?
                var tonalEvidence: [KeyDetector.TonalSegment]?
                if keyOnly {
                    let decoded = try AudioProcessor().readAnalysisAudio(at: file)
                    let limit = maxSeconds.map { Int($0 * decoded.sampleRate) } ?? decoded.samples.count
                    let audio = (samples: Array(decoded.samples.prefix(limit)), sampleRate: decoded.sampleRate,
                                 duration: decoded.duration)
                    (key, confidence) = try await makeDetector().detectKeyWithConfidence(
                        audioSamples: audio.samples, sampleRate: audio.sampleRate)
                    if exportFeatures {
                        tonalEvidence = try await makeDetector().collectTonalEvidence(
                            audioSamples: audio.samples, sampleRate: audio.sampleRate)
                    }
                    duration = audio.duration
                    bpm = nil
                } else {
                    let result = try await AudioProcessor().analyzeAudioFile(at: file)
                    key = result.key
                    confidence = result.confidence
                    duration = result.duration
                    bpm = result.bpm
                }
                unchanged = try fileDigest(file) == before
                try check(unchanged, "Source changed during analysis")
                results.append(Measurement(id: candidate.id, relativePath: candidate.relativePath, audioSHA256: before,
                    sourceUnchanged: unchanged, key: key.rawValue, camelot: key.camelotNotation,
                    bpm: bpm, heuristicConfidence: confidence, duration: duration,
                    elapsedSeconds: Date().timeIntervalSince(started), error: nil, tonalEvidence: tonalEvidence))
            } catch {
                if let before { unchanged = (try? fileDigest(file)) == before }
                results.append(Measurement(id: candidate.id, relativePath: candidate.relativePath, audioSHA256: before,
                    sourceUnchanged: unchanged, key: nil, camelot: nil, bpm: nil, heuristicConfidence: nil,
                    duration: nil, elapsedSeconds: Date().timeIntervalSince(started), error: String(describing: error),
                    tonalEvidence: nil))
            }
            try write(results, to: output.appendingPathComponent("results.json"))
            try report(results, manifest: manifest, directory: output)
            print("BENCHMARK \(results.count)/\(selected.count): \(candidate.relativePath)")
        }
        print("Finished. Report: \(output.appendingPathComponent("report.md").path)")
    } else if command == "compare", args.count == 5 {
        try await compare(manifestURL: URL(fileURLWithPath: args[1]), resultsURL: URL(fileURLWithPath: args[2]),
                          output: URL(fileURLWithPath: args[3]), executable: URL(fileURLWithPath: args[4]))
    } else { throw BenchmarkError.invalid("Invalid arguments") }
} catch {
    fputs("Benchmark failed: \(error)\n", stderr)
    exit(1)
}
