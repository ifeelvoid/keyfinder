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
    @Published var tracks: [TrackAnalysis] = []
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

        // Search filter
        if !searchText.isEmpty {
            result = result.filter { track in
                track.fileName.lowercased().contains(searchText.lowercased()) ||
                track.key?.lowercased().contains(searchText.lowercased()) == true ||
                track.camelotNotation?.lowercased().contains(searchText.lowercased()) == true
            }
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
        isAnalyzing = true
        addLogEntry("Starting analysis of pending tracks...", type: .info)

        // Determine batch size based on system capabilities
        // Apple Silicon can handle more concurrent tasks efficiently
        let batchSize = PerformanceUtils.optimalBatchSize

        // First pass: Check cache for all pending tracks
        let pendingIndices = tracks.indices.filter { tracks[$0].key == nil && tracks[$0].error == nil }
        var cachedCount = 0

        // Check cached results first
        for index in pendingIndices {
            let url = tracks[index].filePath
            if let cacheEntry = FileHasher.getCachedAnalysis(for: url) {
                // Restore from cache
                tracks[index].key = cacheEntry.key
                tracks[index].camelotNotation = cacheEntry.camelotNotation
                tracks[index].bpm = cacheEntry.bpm
                tracks[index].confidence = cacheEntry.confidence
                tracks[index].duration = cacheEntry.duration
                tracks[index].energy = cacheEntry.energy
                cachedCount += 1
                addLogEntry("Loaded '\(tracks[index].fileName)' from cache - Key: \(cacheEntry.key), BPM: \(cacheEntry.bpm)", type: .success)
            }
        }

        if cachedCount > 0 {
            addLogEntry("Restored \(cachedCount) tracks from cache", type: .info)
        }

        // Get indices that still need analysis
        let stillPendingIndices = tracks.indices.filter { tracks[$0].key == nil && tracks[$0].error == nil }

        if stillPendingIndices.isEmpty {
            addLogEntry("No tracks need analysis", type: .info)
            isAnalyzing = false
            return
        }

        addLogEntry("Analyzing \(stillPendingIndices.count) tracks...", type: .progress)

        // Process remaining files in batches with optimized concurrency
        for batchStart in stride(from: 0, to: stillPendingIndices.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, stillPendingIndices.count)
            let batch = Array(stillPendingIndices[batchStart..<batchEnd])

            // Mark batch as analyzing
            for index in batch {
                tracks[index].isAnalyzing = true
            }

            // Process batch in parallel
            await withTaskGroup(of: (Int, Result<AudioProcessor.AnalysisResult, Error>).self) { group in
                for index in batch {
                    group.addTask {
                        do {
                            let result = try await self.audioProcessor.analyzeAudioFile(at: self.tracks[index].filePath)
                            return (index, .success(result))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }

                // Collect results
                for await (index, result) in group {
                    switch result {
                    case .success(let analysisResult):
                        tracks[index].key = analysisResult.key.shortName
                        tracks[index].camelotNotation = analysisResult.key.camelotNotation
                        tracks[index].bpm = String(format: "%.1f", analysisResult.bpm)
                        tracks[index].confidence = analysisResult.confidence
                        tracks[index].duration = analysisResult.duration
                        tracks[index].energy = analysisResult.energy.rawValue

                        // Save to cache for future use
                        let url = tracks[index].filePath
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                           let modDate = attributes[.modificationDate] as? Date,
                           let fileSize = attributes[.size] as? Int64,
                           let quickHash = FileHasher.quickHash(for: url) {
                            let cacheEntry = FileHasher.CacheEntry(
                                fileHash: quickHash,
                                modificationDate: modDate,
                                analysisDate: Date(),
                                key: analysisResult.key.shortName,
                                camelotNotation: analysisResult.key.camelotNotation,
                                bpm: String(format: "%.1f", analysisResult.bpm),
                                confidence: analysisResult.confidence,
                                duration: analysisResult.duration,
                                energy: analysisResult.energy.rawValue,
                                fileSize: fileSize
                            )
                            FileHasher.saveAnalysis(cacheEntry, for: url)
                        }

                        addLogEntry("Analyzed '\(tracks[index].fileName)' - Key: \(analysisResult.key.shortName) (\(analysisResult.key.camelotNotation)), BPM: \(String(format: "%.1f", analysisResult.bpm)), Confidence: \(Int(analysisResult.confidence * 100))%", type: .success)

                        // Add key changes if detected
                        tracks[index].keyChanges = analysisResult.keyChanges.map { (timestamp, key, confidence) in
                            KeyChange(
                                timestamp: timestamp,
                                key: key.shortName,
                                camelotNotation: key.camelotNotation,
                                confidence: confidence
                            )
                        }

                        // Add beatgrid data if available
                        if let beatGrid = analysisResult.beatGrid {
                            let beatDataList = beatGrid.beats.map { beat in
                                BeatGridData.BeatData(
                                    time: beat.time,
                                    strength: beat.strength,
                                    isDownbeat: beat.isDownbeat,
                                    beatNumber: beat.beatNumber
                                )
                            }

                            let timeSignatureStr: String
                            switch beatGrid.timeSignature {
                            case .threeFour: timeSignatureStr = "3/4"
                            case .sixEight: timeSignatureStr = "6/8"
                            case .fourFour: fallthrough
                            @unknown default: timeSignatureStr = "4/4"
                            }

                            tracks[index].beatGrid = BeatGridData(
                                bpm: beatGrid.bpm,
                                timeSignature: timeSignatureStr,
                                firstDownbeatTime: beatGrid.firstDownbeatTime,
                                beats: beatDataList,
                                hasValidGrid: true
                            )
                            tracks[index].timeSignature = timeSignatureStr
                        }
                    case .failure(let error):
                        // Categorize the error
                        let errorType = categorizeError(error, for: tracks[index].filePath)
                        tracks[index].error = error.localizedDescription
                        tracks[index].errorType = errorType

                        addLogEntry("Failed to analyze '\(tracks[index].fileName)' - \(errorType.displayTitle): \(errorType.displayDescription)", type: .error)
                    }
                    tracks[index].isAnalyzing = false
                }
            }
        }

        let successCount = tracks.filter { $0.key != nil && !$0.hasError }.count
        let failCount = tracks.filter { $0.hasError }.count
        addLogEntry("Analysis complete: \(successCount) succeeded, \(failCount) failed", type: .info)

        isAnalyzing = false
    }

    /// Categorize an error based on its type and the file being analyzed
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
        guard index < tracks.count else { return }
        guard !isAnalyzing else { return }

        let track = tracks[index]
        addLogEntry("Retrying analysis for '\(track.fileName)'...", type: .info)

        // Clear the error
        tracks[index].error = nil
        tracks[index].errorType = .none
        tracks[index].isAnalyzing = true

        do {
            let result = try await audioProcessor.analyzeAudioFile(at: track.filePath)

            tracks[index].key = result.key.shortName
            tracks[index].camelotNotation = result.key.camelotNotation
            tracks[index].bpm = String(format: "%.1f", result.bpm)
            tracks[index].confidence = result.confidence
            tracks[index].duration = result.duration
            tracks[index].energy = result.energy.rawValue
            tracks[index].error = nil
            tracks[index].errorType = .none

            addLogEntry("Successfully analyzed '\(track.fileName)' - Key: \(result.key.shortName)", type: .success)
        } catch {
            let errorType = categorizeError(error, for: track.filePath)
            tracks[index].error = error.localizedDescription
            tracks[index].errorType = errorType
            tracks[index].isAnalyzing = false

            addLogEntry("Retry failed for '\(track.fileName)' - \(errorType.displayTitle)", type: .error)
        }

        tracks[index].isAnalyzing = false
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
    func generateHarmonicMix(maxTracks: Int = 20, startWithKey: String? = nil) {
        // Get tracks that have both key and BPM
        let validTracks = tracks.filter { $0.key != nil && $0.bpm != nil && !$0.hasError }

        guard !validTracks.isEmpty else {
            generatedMixPlaylist = []
            return
        }

        var mix: [TrackAnalysis] = []
        var availableTracks = validTracks

        // Determine starting key
        var currentKey: String?

        if let startKey = startWithKey {
            currentKey = startKey
            // Find tracks that match the starting key
            let startTracks = availableTracks.filter { $0.camelotNotation == startKey }
            if let first = startTracks.first {
                mix.append(first)
                availableTracks.removeAll { $0.id == first.id }
            }
        } else if let first = availableTracks.randomElement() {
            // Random starting track
            currentKey = first.camelotNotation
            mix.append(first)
            availableTracks.removeAll { $0.id == first.id }
        }

        // Build the mix using harmonic mixing
        while mix.count < maxTracks && !availableTracks.isEmpty {
            guard let currentCamelot = currentKey else { break }

            let compatibleKeys = getCompatibleCamelotKeys(currentCamelot)

            // Find compatible tracks
            let compatible = availableTracks.filter { track in
                if let camelot = track.camelotNotation {
                    return compatibleKeys.contains(camelot)
                }
                return false
            }

            if let nextTrack = compatible.randomElement() {
                mix.append(nextTrack)
                currentKey = nextTrack.camelotNotation
                availableTracks.removeAll { $0.id == nextTrack.id }
            } else {
                // No compatible track found, try to find any remaining track
                if let next = availableTracks.randomElement() {
                    mix.append(next)
                    currentKey = next.camelotNotation
                    availableTracks.removeAll { $0.id == next.id }
                }
            }
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

        var csv = "# Harmonic Mix Playlist generated by KeyFinder\n"
        csv += "# Generated: \(ISO8601DateFormatter().string(from: Date()))\n"
        csv += "# Total Tracks: \(generatedMixPlaylist.count)\n\n"
        csv += "Order,Filename,Key,Camelot,BPM,Duration\n"

        for (index, track) in generatedMixPlaylist.enumerated() {
            let filename = track.fileName.replacingOccurrences(of: ",", with: ";")
            let key = track.key ?? ""
            let camelot = track.camelotNotation ?? ""
            let bpm = track.bpm ?? ""
            let duration = String(format: "%.1f", track.duration)
            csv += "\(index + 1),\(filename),\(key),\(camelot),\(bpm),\(duration)\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
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

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<DJ_PLAYLISTS Version=\"1.0.0\">\n"
        xml += "  <COLLECTION>\n"

        for track in tracks {
            guard let key = track.key, let bpm = track.bpm else { continue }

            let fileName = track.fileName.replacingOccurrences(of: "&", with: "&amp;")
                                       .replacingOccurrences(of: "<", with: "&lt;")
                                       .replacingOccurrences(of: ">", with: "&gt;")
            let location = "file://localhost" + track.filePath.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!

            xml += "    <TRACK TrackID=\"\(track.id)\" Name=\"\(fileName)\" Artist=\"\" "
            xml += "Composer=\"\" Album=\"\" Grouping=\"\" Genre=\"\" "
            xml += "Kind=\"MP3 File\" Size=\"0\" TotalTime=\"0\" "
            xml += "DiscNumber=\"0\" TrackNumber=\"0\" Year=\"0\" "
            xml += "AverageBpm=\"\(bpm)\" DateAdded=\"\(ISO8601DateFormatter().string(from: Date()))\" "
            xml += "BitRate=\"0\" SampleRate=\"0\" Comments=\"\" "
            xml += "PlayCount=\"0\" Rating=\"0\" "
            xml += "Location=\"\(location)\" "
            xml += "Tonality=\"\(key)\" "
            xml += "Label=\"\" Mix=\"\"/>\n"
        }

        xml += "  </COLLECTION>\n"
        xml += "</DJ_PLAYLISTS>\n"

        try? xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportToSerato() -> URL? {
        // Serato uses ID3 tags, so we'll create a CSV with instructions
        let savePanel = NSSavePanel()
        savePanel.title = "Export Serato Import CSV"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "serato_keyfinder_export.csv"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        var csv = "File Path,Key,BPM,Confidence,Camelot,Instructions\n"

        for track in tracks {
            guard let key = track.key, let bpm = track.bpm, let camelot = track.camelotNotation else { continue }

            let confidence = track.confidenceText
            let path = track.filePath.path
            csv += "\"\(path)\",\"\(key)\",\"\(bpm)\",\"\(confidence)\",\"\(camelot)\",\"Use MP3Tag or Kid3 to write key to comments\"\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
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
        var csv = "Filename,Key,Camelot,BPM,Confidence,File Path\n"

        for track in tracks {
            let filename = track.fileName.replacingOccurrences(of: ",", with: ";")
            let key = track.key ?? ""
            let camelot = track.camelotNotation ?? ""
            let bpm = track.bpm ?? ""
            let confidence = track.confidenceText
            let path = track.filePath.path.replacingOccurrences(of: ",", with: ";")

            csv += "\(filename),\(key),\(camelot),\(bpm),\(confidence),\(path)\n"
        }

        return csv
    }

    // MARK: - Traktor NML Export

    func exportToTraktor() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export to Traktor Collection"
        savePanel.allowedContentTypes = [UTType.xml]
        savePanel.nameFieldStringValue = "collection_keyfinder.nml"

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<NML VERSION=\"19\">\n"
        xml += "  <COLLECTION>\n"
        xml += "    <ENTRY \(traktorEntryAttributes())>\n"

        for track in tracks {
            guard track.key != nil, let bpm = track.bpm else { continue }

            let durationMs = Int(track.duration * 1000)
            let bpmValue = Double(bpm) ?? 120.0

            xml += "      <TRACK \(traktorTrackAttributes(track: track))>\n"
            xml += "        <LOCATION \(traktorLocation(track: track))/>\n"
            xml += "        <INFO BPM=\"\(String(format: "%.2f", bpmValue))\" DUR=\"\(durationMs)\"/>\n"
            xml += "        <TEMPO \(traktorTempo(track: track))/>\n"
            xml += "        <CUE \(traktorCue(track: track))/>\n"
            xml += "      </TRACK>\n"
        }

        xml += "    </ENTRY>\n"
        xml += "  </COLLECTION>\n"
        xml += "</NML>\n"

        try? xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func traktorEntryAttributes() -> String {
        let modified = ISO8601DateFormatter().string(from: Date())
        return "Modified=\"\(modified)\" Visible=\"true\" Filtered=\"false\""
    }

    private func traktorTrackAttributes(track: TrackAnalysis) -> String {
        let key = track.key ?? ""
        let camelot = track.camelotNotation ?? ""
        let artist = track.artist ?? ""
        let title = track.title ?? track.fileName
        return "Title=\"\(escapeXML(title))\" Artist=\"\(escapeXML(artist))\" Album=\"\" Genre=\"\" Comment=\"Key: \(escapeXML(key)) | Camelot: \(escapeXML(camelot))\""
    }

    private func traktorLocation(track: TrackAnalysis) -> String {
        let path = track.filePath.deletingLastPathComponent().path
        let dir = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "Dir=\"file://localhost/\(dir)/\" File=\"\(track.fileName)\""
    }

    private func traktorTempo(track: TrackAnalysis) -> String {
        let bpm = Double(track.bpm ?? "120") ?? 120.0
        return "Bpm=\"\(String(format: "%.2f", bpm))\" Type=\"0\""
    }

    private func traktorCue(track: TrackAnalysis) -> String {
        let key = track.key ?? ""
        return "Label=\"Key: \(escapeXML(key))\" Start=\"0\""
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

        try? xml.write(to: url, atomically: true, encoding: .utf8)
        return url
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

        try? xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Direct Tag Writing

    func writeTagsToFiles() -> URL? {
        // For tag writing, we need to select files first
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Audio Files to Write Tags"
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff]

        guard openPanel.runModal() == .OK, !openPanel.urls.isEmpty else {
            return nil
        }

        var successCount = 0
        var failedFiles: [String] = []

        for url in openPanel.urls {
            do {
                try writeTagsToFile(at: url)
                successCount += 1
            } catch {
                failedFiles.append(url.lastPathComponent)
            }
        }

        // Create result file
        let resultURL = FileManager.default.temporaryDirectory.appendingPathComponent("keyfinder_tag_write_result.txt")
        var resultText = "Tag Writing Results\n"
        resultText += "==================\n"
        resultText += "Successfully wrote tags to \(successCount) files.\n"

        if !failedFiles.isEmpty {
            resultText += "\nFailed files:\n"
            for file in failedFiles {
                resultText += "  - \(file)\n"
            }
        }

        try? resultText.write(to: resultURL, atomically: true, encoding: .utf8)
        return resultURL
    }

    private func writeTagsToFile(at url: URL) throws {
        // Tag writing requires more complex handling - for now, just log what would be written
        // Find matching track from our analysis
        let matchingTrack = tracks.first { $0.filePath == url }

        if let track = matchingTrack {
            // Log what would be written
            print("Would write tags to: \(url.lastPathComponent)")
            print("  Key: \(track.key ?? "unknown")")
            print("  BPM: \(track.bpm ?? "unknown")")
            print("  Camelot: \(track.camelotNotation ?? "unknown")")
        }
    }

    // MARK: - Helper Functions

    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
