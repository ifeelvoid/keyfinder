import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import KeyFinderEngine

// MARK: - DJ Presets

/// Predefined DJ workflow presets for quick filtering
struct DJPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bpmMin: Double
    let bpmMax: Double
    let camelotKeys: [String]
    let icon: String

    static let allPresets: [DJPreset] = [
        DJPreset(name: "HOUSE", bpmMin: 118, bpmMax: 130, camelotKeys: ["8A", "8B", "9A", "9B", "10A", "10B", "11A", "11B"], icon: "house.fill"),
        DJPreset(name: "TECHNO", bpmMin: 130, bpmMax: 145, camelotKeys: ["10A", "10B", "11A", "11B", "12A", "12B", "1A", "1B", "2A"], icon: "waveform.badge.plus"),
        DJPreset(name: "TECHNO 2", bpmMin: 140, bpmMax: 160, camelotKeys: ["11A", "11B", "12A", "12B", "1A", "1B", "2A", "2B"], icon: "waveform.badge.plus"),
        DJPreset(name: "TRANCE", bpmMin: 138, bpmMax: 145, camelotKeys: ["11A", "11B", "12A", "12B", "1A", "1B", "2A", "2B"], icon: "sparkles"),
        DJPreset(name: "DRUM & BASS", bpmMin: 160, bpmMax: 180, camelotKeys: ["11A", "11B", "12A", "12B", "1A", "1B", "2A", "2B", "3A", "3B"], icon: "bolt.fill"),
        DJPreset(name: "HIP-HOP", bpmMin: 80, bpmMax: 100, camelotKeys: ["4A", "4B", "5A", "5B", "6A", "6B", "7A", "7B", "8A", "8B"], icon: "headphones"),
        DJPreset(name: "LOUNGE", bpmMin: 90, bpmMax: 110, camelotKeys: ["6A", "6B", "7A", "7B", "8A", "8B", "9A", "9B"], icon: "sun.max"),
        DJPreset(name: "ALL", bpmMin: 0, bpmMax: 999, camelotKeys: [], icon: "square.grid.2x2")
    ]
}

/// Represents a potential duplicate track
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let tracks: [TrackAnalysis]
    let matchReasons: [String]

    var primaryTrack: TrackAnalysis? { tracks.first }
    var duplicateCount: Int { tracks.count - 1 }
}

/// Log entry for tracking analysis progress
struct AnalysisLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType

    enum LogType: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case success = "SUCCESS"
        case progress = "PROGRESS"
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

@MainActor
class AudioAnalysisModel: ObservableObject {
    @Published var tracks: [TrackAnalysis] = [] {
        didSet {
            if persistenceEnabled {
                generatedMixPlaylist = []
                mixReasons = [:]
            }
            persistLibrary()
        }
    }
    @Published var isAnalyzing = false
    @Published var selectedTrack: TrackAnalysis?
    @Published var searchText = ""
    @Published var filterKey: String?
    @Published var filterBPMMin: Double?
    @Published var filterBPMMax: Double?
    @Published var activePreset: DJPreset?
    @Published var analysisLog: [AnalysisLogEntry] = []

    // Smart DJ features
    @Published var generatedMixPlaylist: [TrackAnalysis] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var isShowingDuplicates = false
    @Published var mixDirection: EnergyDirection = .hold
    @Published var mixReasons: [UUID: String] = [:]
    @Published var libraryWarning: String?

    private let libraryURL: URL
    private var persistenceEnabled = false

    init(libraryURL: URL? = nil) {
        self.libraryURL = libraryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyFinder/library-v2.1.json")
        defer { persistenceEnabled = true }
        guard FileManager.default.fileExists(atPath: self.libraryURL.path) else { return }
        do {
            tracks = try JSONDecoder().decode([TrackAnalysis].self, from: Data(contentsOf: self.libraryURL))
            for index in tracks.indices {
                let fingerprint = FileHasher.quickHash(for: tracks[index].filePath)
                if fingerprint == nil || fingerprint != tracks[index].analysisFingerprint {
                    tracks[index].error = "File changed or is unavailable. Remove and add it again to analyze the current file."
                    tracks[index].errorType = fingerprint == nil ? .fileNotFound : .unknown("File changed")
                }
            }
        } catch {
            libraryWarning = "Saved crate could not be read. It has been preserved on disk."
            // Never overwrite an unreadable crate with an empty one.
            return
        }
    }

    private func persistLibrary() {
        guard persistenceEnabled, libraryWarning == nil else { return }
        do {
            try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(tracks).write(to: libraryURL, options: .atomic)
        } catch { libraryWarning = "Crate changes could not be saved: \(error.localizedDescription)" }
    }

    private let audioProcessor = AudioProcessor()
    private let albumArtExtractor = AlbumArtExtractor()

    // MARK: - Analysis Log Helpers

    private func addLogEntry(_ message: String, type: AnalysisLogEntry.LogType) {
        let entry = AnalysisLogEntry(timestamp: Date(), message: message, type: type)
        analysisLog.append(entry)
        // Keep log to last 1000 entries to prevent memory issues
        if analysisLog.count > 1000 {
            analysisLog.removeFirst(analysisLog.count - 1000)
        }
    }

    func clearLog() {
        analysisLog.removeAll()
    }

    // MARK: - Computed Properties

    var failedTracksCount: Int {
        tracks.filter { $0.hasError }.count
    }

    var succeededTracksCount: Int {
        tracks.filter { $0.key != nil && !$0.hasError }.count
    }

    var pendingTracksCount: Int {
        tracks.filter { $0.key == nil && !$0.hasError && !$0.isAnalyzing }.count
    }

    var failedTracks: [TrackAnalysis] {
        tracks.filter { $0.hasError }
    }

    var filteredTracks: [TrackAnalysis] {
        var result = tracks

        // Search filter: every word must match (name/key text, exact Camelot like "4A",
        // or a BPM range like "140-175").
        let terms = searchText.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if !terms.isEmpty {
            result = result.filter { track in terms.allSatisfy { Self.track(track, matches: $0) } }
        }

        // Key filter
        if let key = filterKey {
            result = result.filter { $0.key == key || $0.camelotNotation == key }
        }

        // BPM filter
        if let minBPM = filterBPMMin {
            result = result.filter { track in
                if let bpm = Double(track.bpm ?? "") {
                    return bpm >= minBPM
                }
                return false
            }
        }

        if let maxBPM = filterBPMMax {
            result = result.filter { track in
                if let bpm = Double(track.bpm ?? "") {
                    return bpm <= maxBPM
                }
                return false
            }
        }

        // Active preset filter (apply preset BPM range and camelot keys)
        if let preset = activePreset, !preset.camelotKeys.isEmpty {
            result = result.filter { track in
                // BPM range check
                if let bpm = Double(track.bpm ?? "") {
                    if bpm < preset.bpmMin || bpm > preset.bpmMax {
                        return false
                    }
                } else {
                    return false
                }

                // Camelot key check
                if let camelot = track.camelotNotation {
                    return preset.camelotKeys.contains(camelot)
                }
                return false
            }
        }

        return result
    }

    static func track(_ track: TrackAnalysis, matches term: String) -> Bool {
        let range = term.split(separator: "-", omittingEmptySubsequences: false)
        if range.count == 2, let low = Double(range[0]), let high = Double(range[1]) {
            guard let bpm = Double(track.bpm ?? "") else { return false }
            return bpm >= min(low, high) && bpm <= max(low, high)
        }
        let isCamelot = term.count <= 3 && (term.hasSuffix("a") || term.hasSuffix("b"))
            && Int(term.dropLast()).map { (1...12).contains($0) } == true
        if isCamelot { return track.camelotNotation?.lowercased() == term }
        return track.fileName.lowercased().contains(term)
            || track.key?.lowercased().contains(term) == true
            || track.camelotNotation?.lowercased().contains(term) == true
    }

    // MARK: - Preset Filtering

    func applyPreset(_ preset: DJPreset) {
        if preset.name == "ALL" {
            activePreset = nil
            filterBPMMin = nil
            filterBPMMax = nil
            filterKey = nil
        } else {
            activePreset = preset
            filterBPMMin = preset.bpmMin
            filterBPMMax = preset.bpmMax
            filterKey = nil
        }
    }

    func clearPreset() {
        activePreset = nil
    }

    func addFiles(_ urls: [URL]) async {
        for url in urls {
            guard !tracks.contains(where: { $0.filePath.standardizedFileURL == url.standardizedFileURL }) else { continue }
            let track = TrackAnalysis(
                fileName: url.lastPathComponent,
                filePath: url,
                albumArt: albumArtExtractor.extractAlbumArt(from: url)
            )

            tracks.append(track)
        }

        // Auto-analyze all new tracks
        await analyzeAllPending()
    }

    func analyzeAllPending() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        // Stable IDs survive removal/reordering during an await. Bound memory across files.
        while let track = tracks.first(where: { $0.key == nil && !$0.hasError }) {
            guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { continue }
            tracks[index].isAnalyzing = true
            do {
                let result = try await audioProcessor.analyzeAudioFile(at: track.filePath, keyStyle: KeyStyle.stored())
                guard let current = tracks.firstIndex(where: { $0.id == track.id }) else { continue }
                apply(result, at: current)
                addLogEntry("Prepared '\(track.fileName)' — \(result.key.shortName), \(String(format: "%.1f", result.bpm)) BPM", type: .success)
            } catch {
                if let current = tracks.firstIndex(where: { $0.id == track.id }) {
                    tracks[current].error = error.localizedDescription
                    tracks[current].errorType = categorizeError(error, for: track.filePath)
                    tracks[current].isAnalyzing = false
                }
                addLogEntry("Analysis failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func apply(_ result: AudioProcessor.AnalysisResult, at index: Int) {
        var track = tracks[index]
        track.key = result.key.shortName
        track.camelotNotation = result.key.camelotNotation
        track.bpm = String(format: "%.1f", result.bpm)
        track.detectedKey = track.key
        track.detectedCamelot = track.camelotNotation
        track.detectedBPM = track.bpm
        track.analysisFingerprint = FileHasher.quickHash(for: track.filePath)
        track.confidence = result.confidence
        track.duration = result.duration
        track.energy = result.energy.rawValue
        track.error = nil
        track.errorType = .none
        track.isAnalyzing = false
        track.keyChanges = result.keyChanges.map { KeyChange(timestamp: $0.0, key: $0.1.shortName, camelotNotation: $0.1.camelotNotation, confidence: $0.2) }
        if let grid = result.beatGrid {
            let signature = grid.timeSignature == .threeFour ? "3/4" : grid.timeSignature == .sixEight ? "6/8" : "4/4"
            track.beatGrid = BeatGridData(bpm: grid.bpm, timeSignature: signature,
                                         firstDownbeatTime: grid.firstDownbeatTime,
                                         beats: grid.beats.map { .init(time: $0.time, strength: $0.strength, isDownbeat: $0.isDownbeat, beatNumber: $0.beatNumber) },
                                         hasValidGrid: !grid.beats.isEmpty)
            track.timeSignature = signature
        }
        // Reanalysis preserves approved/manual cues, replacing only unconfirmed suggestions.
        track.cuePoints.removeAll { $0.isSuggested }
        for suggestion in result.suggestedCues where track.cuePoints.count < 8 {
            guard track.cuePoints.allSatisfy({ abs($0.timestamp - suggestion.time) > 1 }) else { continue }
            var cue = CuePoint(timestamp: suggestion.time, name: suggestion.name)
            cue.isSuggested = true
            track.cuePoints.append(cue)
        }
        tracks[index] = track
    }

    private func categorizeError(_ error: Error, for url: URL) -> AnalysisErrorType {
        let errorMessage = error.localizedDescription.lowercased()

        // Check file existence
        if !FileManager.default.fileExists(atPath: url.path) {
            return .fileNotFound
        }

        // Check file extension
        let supportedExtensions = ["mp3", "wav", "m4a", "flac", "aiff", "aif"]
        if !supportedExtensions.contains(url.pathExtension.lowercased()) {
            return .unsupportedFormat
        }

        // Check for specific error patterns
        if errorMessage.contains("not found") || errorMessage.contains("no such file") {
            return .fileNotFound
        }

        if errorMessage.contains("permission") || errorMessage.contains("access") {
            return .permissionDenied
        }

        if errorMessage.contains("corrupt") || errorMessage.contains("invalid") || errorMessage.contains("malformed") {
            return .fileTooCorrupt
        }

        if errorMessage.contains("short") || errorMessage.contains("too small") || errorMessage.contains("length") {
            return .fileTooShort
        }

        if errorMessage.contains("timeout") || errorMessage.contains("cancelled") {
            return .analysisTimeout
        }

        if errorMessage.contains("no audio") || errorMessage.contains("empty") || errorMessage.contains("data") {
            return .noAudioData
        }

        return .unknown(error.localizedDescription)
    }

    // MARK: - Retry Failed Tracks

    func retryFailedTracks() async {
        guard !isAnalyzing else { return }

        addLogEntry("Retrying failed tracks...", type: .info)

        // Clear errors and reset failed tracks
        for index in tracks.indices {
            if tracks[index].hasError {
                tracks[index].key = nil
                tracks[index].error = nil
                tracks[index].errorType = .none
            }
        }

        // Re-analyze
        await analyzeAllPending()
    }

    // MARK: - Skip Failed Tracks

    func skipFailedTracks() {
        let failedCount = failedTracksCount
        addLogEntry("Skipping \(failedCount) failed tracks...", type: .warning)

        // Remove failed tracks from the list
        tracks.removeAll { $0.hasError }

        addLogEntry("Removed \(failedCount) failed tracks from the list", type: .info)
    }

    // MARK: - Retry Single Track

    func retryTrack(at index: Int) async {
        guard tracks.indices.contains(index), !isAnalyzing else { return }
        tracks[index].error = nil
        tracks[index].errorType = .none
        tracks[index].key = nil
        await analyzeAllPending()
    }

    func clearAll() {
        tracks.removeAll()
        generatedMixPlaylist.removeAll()
        duplicateGroups.removeAll()
        activePreset = nil
    }

    // MARK: - Smart Playlists: Harmonic Mix Generation

    /// Generates a harmonically mixed playlist from analyzed tracks
    /// - Parameters:
    ///   - maxTracks: Maximum number of tracks in the mix (default 20)
    ///   - startWithKey: Optional camelot key to start the mix with
    /// - Returns: Array of tracks arranged for harmonic mixing
    func transition(from: TrackAnalysis, to: TrackAnalysis) -> TransitionAssessment? {
        guard !from.hasError, !to.hasError, let fromKey = from.camelotNotation, let toKey = to.camelotNotation,
              let fromBPM = Double(from.bpm ?? ""), let toBPM = Double(to.bpm ?? "") else { return nil }
        return MixRanker.assess(fromKey: fromKey, fromBPM: fromBPM, fromEnergy: from.energy,
                                toKey: toKey, toBPM: toBPM, toEnergy: to.energy, direction: mixDirection)
    }

    func generateHarmonicMix(maxTracks: Int = 20, startWithKey: String? = nil) {
        let valid = tracks.filter { $0.key != nil && (Double($0.bpm ?? "") ?? 0) > 0 && !$0.hasError }
            .sorted { $0.filePath.path < $1.filePath.path }
        generatedMixPlaylist = []
        mixReasons = [:]
        guard maxTracks > 0, let first = valid.first(where: { startWithKey == nil || $0.camelotNotation == startWithKey }) else { return }
        var mix = [first]
        mixReasons[first.id] = "Starting track"
        while mix.count < maxTracks {
            let current = mix.last!
            let candidates = valid.filter { candidate in !mix.contains(where: { $0.id == candidate.id }) }
                .compactMap { candidate -> (TrackAnalysis, TransitionAssessment)? in
                    guard let assessment = transition(from: current, to: candidate) else { return nil }
                    return (candidate, assessment)
                }
                .sorted { $0.1.score == $1.1.score ? $0.0.filePath.path < $1.0.filePath.path : $0.1.score > $1.1.score }
            guard let next = candidates.first else { break }
            mix.append(next.0)
            mixReasons[next.0.id] = next.1.reasons.joined(separator: " · ")
        }
        generatedMixPlaylist = mix
    }

    /// Exports the generated mix playlist to a file
    func exportMixPlaylist() -> URL? {
        guard !generatedMixPlaylist.isEmpty else { return nil }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Harmonic Mix Playlist"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "harmonic_mix_\(Date().timeIntervalSince1970).csv"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        let rows = [["Order", "Filename", "Key", "Camelot", "BPM", "Duration", "Transition reason"]] +
            generatedMixPlaylist.enumerated().map { index, track in
                [String(index + 1), track.fileName, track.key ?? "", track.camelotNotation ?? "", track.bpm ?? "",
                 String(format: "%.1f", track.duration), mixReasons[track.id] ?? ""]
            }
        return writeExport(DJExport.csv(rows), to: url)
    }

    // MARK: - Duplicate Detection

    /// Detects potential duplicate tracks based on key + BPM + duration + filename similarity
    /// - Parameters:
    ///   - bpmTolerance: BPM difference allowed for match (default 0.5)
    ///   - durationTolerance: Duration difference in seconds (default 2.0)
    ///   - filenameSimilarity: Minimum similarity ratio (0.0-1.0, default 0.7)
    func detectDuplicates(
        bpmTolerance: Double = 0.5,
        durationTolerance: Double = 2.0,
        filenameSimilarity: Double = 0.7
    ) {
        duplicateGroups.removeAll()

        var processed = Set<UUID>()
        var groups: [DuplicateGroup] = []

        // Group 1: Exact or near-exact matches (same filename, key, BPM, duration)
        for track in tracks {
            guard !processed.contains(track.id) else { continue }
            guard track.key != nil && track.bpm != nil else { continue }

            var matches: [TrackAnalysis] = [track]
            var matchReasons: [String] = []
            matchReasons.append("Base track")

            for otherTrack in tracks {
                guard track.id != otherTrack.id else { continue }
                guard !processed.contains(otherTrack.id) else { continue }
                guard otherTrack.key != nil && otherTrack.bpm != nil else { continue }

                var reasons: [String] = []

                // Check filename similarity
                let similarity = calculateFilenameSimilarity(track.fileName, otherTrack.fileName)
                let hasSimilarName = similarity >= filenameSimilarity

                // Check BPM match
                let bpmMatch: Bool
                if let bpm1 = Double(track.bpm ?? ""),
                   let bpm2 = Double(otherTrack.bpm ?? "") {
                    bpmMatch = abs(bpm1 - bpm2) <= bpmTolerance
                } else {
                    bpmMatch = false
                }

                // Check duration match
                let durationMatch = abs(track.duration - otherTrack.duration) <= durationTolerance

                // Check key match
                let keyMatch = track.camelotNotation == otherTrack.camelotNotation

                // Determine if it's a duplicate
                var isDuplicate = false

                if hasSimilarName && bpmMatch {
                    isDuplicate = true
                    if similarity >= 0.9 {
                        reasons.append("Very similar filename")
                    } else {
                        reasons.append("Similar filename")
                    }
                    reasons.append(bpmMatch ? "Matching BPM" : "Similar BPM")
                } else if hasSimilarName && keyMatch {
                    isDuplicate = true
                    reasons.append("Similar filename")
                    reasons.append("Same key")
                } else if keyMatch && bpmMatch && durationMatch && hasSimilarName {
                    isDuplicate = true
                    reasons.append("Same key, BPM, duration")
                }

                if isDuplicate {
                    matches.append(otherTrack)
                    processed.insert(otherTrack.id)
                    matchReasons.append(contentsOf: reasons)
                }
            }

            if matches.count > 1 {
                groups.append(DuplicateGroup(tracks: matches, matchReasons: Array(Set(matchReasons))))
                processed.insert(track.id)
            }
        }

        duplicateGroups = groups
    }

    /// Calculate similarity between two filenames (0.0 to 1.0)
    private func calculateFilenameSimilarity(_ s1: String, _ s2: String) -> Double {
        let normalized1 = s1.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let normalized2 = s2.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")

        // Exact match
        if normalized1 == normalized2 { return 1.0 }

        // Levenshtein distance based similarity
        let distance = levenshteinDistance(normalized1, normalized2)
        let maxLength = max(normalized1.count, normalized2.count)

        if maxLength == 0 { return 0 }

        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    /// Export duplicates report
    func exportDuplicatesReport() -> URL? {
        guard !duplicateGroups.isEmpty else { return nil }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Duplicates Report"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "duplicates_report_\(Date().timeIntervalSince1970).csv"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        var csv = "# Duplicate Tracks Report generated by KeyFinder\n"
        csv += "# Generated: \(ISO8601DateFormatter().string(from: Date()))\n"
        csv += "# Total Duplicate Groups: \(duplicateGroups.count)\n\n"

        for (groupIndex, group) in duplicateGroups.enumerated() {
            csv += "# Group \(groupIndex + 1) - \(group.duplicateCount) duplicate(s)\n"
            csv += "Group,Filename,Key,Camelot,BPM,Duration,FilePath\n"

            for (_, track) in group.tracks.enumerated() {
                let filename = track.fileName.replacingOccurrences(of: ",", with: ";")
                let key = track.key ?? ""
                let camelot = track.camelotNotation ?? ""
                let bpm = track.bpm ?? ""
                let duration = String(format: "%.1f", track.duration)
                let path = track.filePath.path.replacingOccurrences(of: ",", with: ";")
                csv += "\(groupIndex + 1),\(filename),\(key),\(camelot),\(bpm),\(duration),\(path)\n"
            }
            csv += "\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func removeTrack(at index: Int) {
        tracks.remove(at: index)
    }

    func updateAlbumArt(at index: Int, image: NSImage) {
        guard index < tracks.count else { return }
        tracks[index].albumArt = image
    }

    func selectTrackForHarmonicMixing(_ track: TrackAnalysis) {
        selectedTrack = track
        updateCompatibleTracks()
    }

    func clearSelection() {
        selectedTrack = nil
        for i in tracks.indices {
            tracks[i].isCompatible = false
        }
    }

    private func updateCompatibleTracks() {
        guard let selected = selectedTrack, let camelot = selected.camelotNotation else {
            return
        }

        let compatible = getCompatibleCamelotKeys(camelot)

        for i in tracks.indices {
            if let trackCamelot = tracks[i].camelotNotation {
                tracks[i].isCompatible = compatible.contains(trackCamelot)
            }
        }
    }

    private func getCompatibleCamelotKeys(_ camelot: String) -> [String] {
        // Parse Camelot notation (e.g., "8A")
        guard camelot.count >= 2 else { return [] }

        let numberPart = camelot.dropLast()
        let letterPart = camelot.last!

        guard let number = Int(numberPart) else { return [] }

        var compatible: [String] = []

        // Same key
        compatible.append(camelot)

        // ±1 same letter (energy change)
        let prevNumber = number == 1 ? 12 : number - 1
        let nextNumber = number == 12 ? 1 : number + 1
        compatible.append("\(prevNumber)\(letterPart)")
        compatible.append("\(nextNumber)\(letterPart)")

        // Relative major/minor (same number, different letter)
        let otherLetter = letterPart == "A" ? "B" : "A"
        compatible.append("\(number)\(otherLetter)")

        return compatible
    }

    func exportToRekordbox() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export to Rekordbox XML"
        savePanel.allowedContentTypes = [.xml]
        savePanel.nameFieldStringValue = "rekordbox_keyfinder_export.xml"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        return writeExport(DJExport.rekordbox(exportTracks), to: url)
    }

    private var exportTracks: [DJExportTrack] {
        tracks.compactMap { track in
            guard !track.hasError, let key = track.key, let bpm = Double(track.bpm ?? "") else { return nil }
            return DJExportTrack(path: track.filePath, name: track.title ?? track.fileName,
                                 artist: track.artist ?? "", key: key, bpm: bpm, duration: track.duration,
                                 cues: track.cuePoints.filter { !$0.isSuggested }.map { CueSuggestion(time: $0.timestamp, name: $0.name) },
                                 firstDownbeat: track.beatGrid?.hasValidGrid == true ? track.beatGrid?.firstDownbeatTime : nil,
                                 meter: track.timeSignature ?? "4/4")
        }
    }

    private func writeExport(_ content: String, to url: URL) -> URL? {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            guard try String(contentsOf: url, encoding: .utf8) == content else {
                throw NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export verification failed"])
            }
            return url
        } catch {
            addLogEntry("Export failed: \(error.localizedDescription)", type: .error)
            let alert = NSAlert()
            alert.messageText = "Export could not be saved"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return nil
        }
    }

    func exportToSerato() -> URL? {
        // Serato uses ID3 tags, so we'll create a CSV with instructions
        let savePanel = NSSavePanel()
        savePanel.title = "Export Serato Reference CSV (not a native import)"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "serato_keyfinder_export.csv"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        let rows = [["File Path", "Key", "BPM", "Camelot", "Notes"]] + tracks.filter { !$0.hasError && $0.key != nil }.map {
            [$0.filePath.path, $0.key ?? "", $0.bpm ?? "", $0.camelotNotation ?? "",
             "Reference only: CSV does not import Serato tags or cue points."]
        }
        return writeExport(DJExport.csv(rows), to: url)
    }

    func exportToCSV() -> URL? {
        let csv = generateCSV()
        let filename = "keyfinder_export_\(Date().timeIntervalSince1970).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    private func generateCSV() -> String {
        DJExport.csv([["Filename", "Key", "Camelot", "BPM", "Confidence (algorithm score)", "File Path", "Artist", "Title", "Comment"]] +
            tracks.filter { !$0.hasError }.map { [$0.fileName, $0.key ?? "", $0.camelotNotation ?? "", $0.bpm ?? "",
                            $0.confidenceText, $0.filePath.path, $0.artist ?? "", $0.title ?? "", $0.comment ?? ""] })
    }

    // MARK: - Traktor NML Export

    func exportToTraktor() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Traktor NML (import verification pending)"
        savePanel.allowedContentTypes = [UTType.xml]
        savePanel.nameFieldStringValue = "collection_keyfinder.nml"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        return writeExport(DJExport.traktor(exportTracks), to: url)
    }

    // MARK: - Engine DJ Export (JSON)

    func exportToEngineDJ() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export to Engine DJ"
        savePanel.allowedContentTypes = [UTType.json]
        savePanel.nameFieldStringValue = "keyfinder_engine_db.json"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        var tracksArray: [[String: Any]] = []

        for track in tracks {
            guard track.key != nil && track.bpm != nil else { continue }

            let trackDict: [String: Any] = [
                "path": track.filePath.path,
                "filename": track.fileName,
                "title": track.title ?? track.fileName,
                "artist": track.artist ?? "",
                "album": "",
                "genre": track.genre ?? "",
                "year": track.year ?? "",
                "bpm": Double(track.bpm ?? "0") ?? 0.0,
                "key": track.key ?? "",
                "camelot": track.camelotNotation ?? "",
                "duration": track.duration,
                "comment": "Analyzed with KeyFinder"
            ]
            tracksArray.append(trackDict)
        }

        let exportData: [String: Any] = [
            "version": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "trackCount": tracksArray.count,
            "tracks": tracksArray
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Virtual DJ Export (XML)

    func exportToVirtualDJ() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export to Virtual DJ Database"
        savePanel.allowedContentTypes = [UTType.xml]
        savePanel.nameFieldStringValue = "keyfinder_vdj_database.xml"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<VDJ DatabaseVersion=\"8.0\">\n"
        xml += "  <Songs>\n"

        for track in tracks {
            guard let key = track.key, let bpm = track.bpm else { continue }

            let path = track.filePath.path
            let title = track.title ?? track.fileName
            let artist = track.artist ?? ""
            let durationMs = Int(track.duration * 1000)

            xml += "    <Song Id=\"\(track.id.uuidString)\">\n"
            xml += "      <FilePath>\(escapeXML(path))</FilePath>\n"
            xml += "      <Title>\(escapeXML(title))</Title>\n"
            xml += "      <Artist>\(escapeXML(artist))</Artist>\n"
            xml += "      <Album></Album>\n"
            xml += "      <Genre>\(escapeXML(track.genre ?? ""))</Genre>\n"
            xml += "      <Year>\(escapeXML(track.year ?? ""))</Year>\n"
            xml += "      <Length>\(durationMs)</Length>\n"
            xml += "      <Bpm>\(escapeXML(bpm))</Bpm>\n"
            xml += "      <Tonality>\(escapeXML(key))</Tonality>\n"
            xml += "      <Comment>Analyzed with KeyFinder | Camelot: \(escapeXML(track.camelotNotation ?? ""))</Comment>\n"
            xml += "    </Song>\n"
        }

        xml += "  </Songs>\n"
        xml += "</VDJ>\n"

        return writeExport(xml, to: url)
    }

    // MARK: - iTunes-compatible XML Export

    func exportToiTunes() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export to iTunes XML"
        savePanel.allowedContentTypes = [UTType.xml]
        savePanel.nameFieldStringValue = "keyfinder_itunes.xml"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        xml += "<plist version=\"1.0\">\n"
        xml += "<dict>\n"
        xml += "  <key>Application Version</key><string>1.0</string>\n"
        xml += "  <key>Date</key><date>\(now)</date>\n"
        xml += "  <key>Library Persistent ID</key><string>0000000000000001</string>\n"
        xml += "  <key>Tracks</key>\n"
        xml += "  <dict>\n"

        for track in tracks {
            guard let key = track.key, let bpm = track.bpm else { continue }

            let trackId = abs(track.filePath.path.hashValue)
            let durationSec = Int(track.duration)

            xml += "    <key>\(trackId)</key>\n"
            xml += "    <dict>\n"
            xml += "      <key>Track ID</key><integer>\(trackId)</integer>\n"
            xml += "      <key>Name</key><string>\(escapeXML(track.fileName))</string>\n"
            xml += "      <key>Artist</key><string>\(escapeXML(track.artist ?? ""))</string>\n"
            xml += "      <key>Album</key><string></string>\n"
            xml += "      <key>Genre</key><string>\(escapeXML(track.genre ?? ""))</string>\n"
            xml += "      <key>Year</key><integer>\(Int(track.year ?? "0") ?? 0)</integer>\n"
            xml += "      <key>Total Time</key><integer>\(durationSec * 1000)</integer>\n"
            xml += "      <key>BPM</key><integer>\(Int((Double(bpm) ?? 0) * 100))</integer>\n"
            xml += "      <key>Location</key><string>file://localhost\(escapeXML(track.filePath.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? track.filePath.path))</string>\n"
            xml += "      <key>Comments</key><string>Key: \(escapeXML(key)) | Camelot: \(escapeXML(track.camelotNotation ?? "")) | Analyzed with KeyFinder</string>\n"
            xml += "    </dict>\n"
        }

        xml += "  </dict>\n"
        xml += "</dict>\n"
        xml += "</plist>\n"

        return writeExport(xml, to: url)
    }

    // Metadata edits live in the crate. Audio tag writes are not implemented.
    // A reference plan must never be reported as a successful audio-file write.
    func exportMetadataPlan() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Metadata Plan (audio files unchanged)"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "keyfinder_metadata_plan.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return writeExport(generateCSV(), to: url)
    }

    // MARK: - Helper Functions

    private func escapeXML(_ string: String) -> String {
        DJExport.xmlText(string)
    }
}
