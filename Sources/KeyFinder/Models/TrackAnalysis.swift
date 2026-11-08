import Foundation
import AppKit

struct KeyChange: Identifiable, Codable {
    var id = UUID()
    let timestamp: TimeInterval
    let key: String
    let camelotNotation: String
    let confidence: Double
}

struct CuePoint: Identifiable, Codable {
    let id: UUID
    var timestamp: TimeInterval
    var name: String
    var color: String // Rekordbox compatible colors
    var isSuggested: Bool = false

    init(id: UUID = UUID(), timestamp: TimeInterval, name: String, color: String = "purple") {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.color = color
    }
}

/// Beat grid data for DJ use - represents beats, downbeats, and phase
struct BeatGridData: Codable {
    let bpm: Double
    let timeSignature: String // "4/4", "3/4", "6/8"
    let firstDownbeatTime: TimeInterval
    let beats: [BeatData]
    let hasValidGrid: Bool

    struct BeatData: Codable {
        let time: TimeInterval
        let strength: Float
        let isDownbeat: Bool
        let beatNumber: Int // 1, 2, 3, or 4 within the bar
    }

    init(bpm: Double, timeSignature: String, firstDownbeatTime: TimeInterval, beats: [BeatData], hasValidGrid: Bool = true) {
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.firstDownbeatTime = firstDownbeatTime
        self.beats = beats
        self.hasValidGrid = hasValidGrid
    }

    /// Get beat number at a given time
    func beatNumber(at time: TimeInterval) -> Int {
        guard !beats.isEmpty else { return 1 }

        for beat in beats.reversed() {
            if beat.time <= time {
                return beat.beatNumber
            }
        }
        return 1
    }

    /// Get phase (0.0-1.0) at a given time
    func phase(at time: TimeInterval) -> Double {
        guard !beats.isEmpty else { return 0.0 }

        let beatDuration = 60.0 / bpm
        let timeSinceDownbeat = time - firstDownbeatTime
        let beatsSinceDownbeat = timeSinceDownbeat / beatDuration

        return beatsSinceDownbeat.truncatingRemainder(dividingBy: 1.0)
    }

    /// Get time until next downbeat
    func timeToNextDownbeat(from time: TimeInterval) -> TimeInterval {
        let beatsPerBar = timeSignature == "3/4" ? 3 : (timeSignature == "6/8" ? 6 : 4)
        let barDuration = (60.0 / bpm) * Double(beatsPerBar)
        let timeSinceFirstDownbeat = time - firstDownbeatTime
        let barsSinceDownbeat = timeSinceFirstDownbeat / barDuration

        let currentBar = Int(barsSinceDownbeat)
        let nextDownbeatTime = firstDownbeatTime + Double(currentBar + 1) * barDuration

        return nextDownbeatTime - time
    }
}

/// Detailed error types for track analysis failures
enum AnalysisErrorType: Equatable {
    case none
    case fileNotFound
    case unsupportedFormat
    case fileTooShort
    case fileTooCorrupt
    case noAudioData
    case analysisTimeout
    case permissionDenied
    case unknown(String)

    var displayTitle: String {
        switch self {
        case .none: return "No Error"
        case .fileNotFound: return "File Not Found"
        case .unsupportedFormat: return "Unsupported Format"
        case .fileTooShort: return "File Too Short"
        case .fileTooCorrupt: return "Corrupt File"
        case .noAudioData: return "No Audio Data"
        case .analysisTimeout: return "Analysis Timeout"
        case .permissionDenied: return "Permission Denied"
        case .unknown: return "Unknown Error"
        }
    }

    var displayDescription: String {
        switch self {
        case .none: return ""
        case .fileNotFound: return "The audio file could not be found at the specified path. The file may have been moved or deleted."
        case .unsupportedFormat: return "This audio format is not supported. Please use MP3, WAV, M4A, FLAC, AIFF, or AIF files."
        case .fileTooShort: return "The audio file is too short for accurate key detection. Files must be at least 10 seconds long."
        case .fileTooCorrupt: return "The audio file appears to be corrupted or incomplete. Key detection requires a playable audio file."
        case .noAudioData: return "No audio data could be extracted from this file. The file may be empty or contain no valid audio streams."
        case .analysisTimeout: return "The analysis took too long and was cancelled. The file may be too large or complex."
        case .permissionDenied: return "Permission was denied to read this file. Check the file permissions."
        case .unknown(let message): return message
        }
    }

    var iconName: String {
        switch self {
        case .none: return "checkmark.circle"
        case .fileNotFound: return "doc.questionmark"
        case .unsupportedFormat: return "questionmark.circle"
        case .fileTooShort: return "timer"
        case .fileTooCorrupt: return "exclamationmark.triangle"
        case .noAudioData: return "waveform.badge.exclamationmark"
        case .analysisTimeout: return "clock.badge.exclamationmark"
        case .permissionDenied: return "lock.slash"
        case .unknown: return "exclamationmark.circle"
        }
    }
}

struct TrackAnalysis: Identifiable, Codable {
    var id = UUID()
    let fileName: String
    let filePath: URL
    var albumArt: NSImage?
    var key: String?
    var camelotNotation: String?
    var bpm: String?
    var confidence: Double?
    var isAnalyzing: Bool = false
    var error: String?
    var errorType: AnalysisErrorType = .none
    var isCompatible: Bool = false // For harmonic mixing highlighting
    var keyChanges: [KeyChange] = [] // Multiple keys if song modulates
    var duration: TimeInterval = 0 // Track duration in seconds
    var cuePoints: [CuePoint] = [] // User-created cue points
    var tags: [String] = [] // User-added tags (genre, mood, etc.)
    var artist: String?
    var title: String?
    var genre: String?
    var year: String?
    var comment: String?
    var energy: String? // Low, Medium, High, Very High
    var detectedKey: String?
    var detectedCamelot: String?
    var detectedBPM: String?
    var analysisFingerprint: String?

    // App-only/transient state is never stored in the crate snapshot.
    enum CodingKeys: String, CodingKey {
        case id, fileName, filePath, key, camelotNotation, bpm, confidence, keyChanges
        case duration, cuePoints, tags, artist, title, genre, year, comment, energy
        case beatGrid, timeSignature, detectedKey, detectedCamelot, detectedBPM, analysisFingerprint
    }

    // Beatgrid and phase data
    var beatGrid: BeatGridData?
    var timeSignature: String? // "4/4", "3/4", "6/8"

    var hasError: Bool {
        error != nil || errorType != .none
    }

    var shortFileName: String {
        let name = fileName
        if name.count > 30 {
            let start = name.prefix(27)
            return "\(start)..."
        }
        return name
    }

    var confidenceText: String {
        guard let conf = confidence else { return "" }
        let percentage = Int(conf * 100)
        return "\(percentage)%"
    }

    var confidenceColor: String {
        guard let conf = confidence else { return "gray" }
        if conf > 0.75 { return "green" }  // Lowered from 0.8 - improved algorithm gives higher scores
        if conf > 0.50 { return "yellow" } // Lowered from 0.6
        return "red"
    }
}
