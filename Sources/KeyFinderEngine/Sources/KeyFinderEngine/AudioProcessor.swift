import Foundation
import AVFoundation

/// Read a continuous, rate-converted timeline. Disconnected excerpts must never
/// masquerade as contiguous audio for beat-grid or cue placement.
public final class AudioProcessor {
    public enum EnergyLevel: String { case low = "Low", medium = "Medium", high = "High", veryHigh = "Very High" }

    public struct AnalysisResult {
        public let key: KeyDetector.MusicalKey
        public let bpm: Double
        public let fileName: String
        public let confidence: Double
        public let keyChanges: [(TimeInterval, KeyDetector.MusicalKey, Double)]
        public let duration: TimeInterval
        public let energy: EnergyLevel
        public let beatGrid: BeatGridDetector.BeatGrid?
        public let suggestedCues: [CueSuggestion]

        public init(key: KeyDetector.MusicalKey, bpm: Double, fileName: String, confidence: Double,
                    keyChanges: [(TimeInterval, KeyDetector.MusicalKey, Double)], duration: TimeInterval,
                    energy: EnergyLevel, beatGrid: BeatGridDetector.BeatGrid?, suggestedCues: [CueSuggestion] = []) {
            self.key = key; self.bpm = bpm; self.fileName = fileName; self.confidence = confidence
            self.keyChanges = keyChanges; self.duration = duration; self.energy = energy
            self.beatGrid = beatGrid; self.suggestedCues = suggestedCues
        }
    }

    public struct StreamingConfig {
        public let chunkDuration: TimeInterval
        public let overlap: TimeInterval
        public let maxMemoryMB: Int
        public static let `default` = StreamingConfig(chunkDuration: 30, overlap: 5, maxMemoryMB: 512)
        public static let lowMemory = StreamingConfig(chunkDuration: 15, overlap: 2, maxMemoryMB: 256)
        public init(chunkDuration: TimeInterval, overlap: TimeInterval, maxMemoryMB: Int) {
            self.chunkDuration = chunkDuration; self.overlap = overlap; self.maxMemoryMB = maxMemoryMB
        }
    }
    private var streamingConfig: StreamingConfig = .default
    public init() {}
    public func setStreamingMode(config: StreamingConfig) { streamingConfig = config }

    /// `keyStyle` picks the template set / method adopted for that style (default EDM keeps legacy callers unchanged).
    public func analyzeAudioFile(at url: URL, keyStyle: KeyStyle = .edm) async throws -> AnalysisResult {
        let audio = try readAnalysisAudio(at: url)
        try Task.checkCancellation()
        async let keyResult = KeyDetector.configured(for: keyStyle).detectKeyWithChanges(audioSamples: audio.samples, sampleRate: audio.sampleRate)
        let bpm = try await BPMDetector().detectBPM(audioSamples: audio.samples, sampleRate: audio.sampleRate)
        let grid = try await BeatGridDetector().detectBeatGrid(audioSamples: audio.samples, sampleRate: audio.sampleRate, detectedBPM: bpm > 0 ? bpm : nil)
        let (key, confidence, changes) = try await keyResult
        let rms = sqrt(audio.samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(audio.samples.count))
        let energy: EnergyLevel = rms > 0.12 ? .veryHigh : rms > 0.07 ? .high : rms > 0.03 ? .medium : .low
        let cues = CuePlanner.suggest(samples: audio.samples, sampleRate: audio.sampleRate, grid: grid.beatGrid)
        return AnalysisResult(key: key, bpm: bpm, fileName: url.lastPathComponent,
                              confidence: confidence, keyChanges: changes, duration: audio.duration,
                              energy: energy, beatGrid: grid.beatGrid, suggestedCues: cues)
    }

    public func analyzeAudioFileStreaming(at url: URL) async throws -> AnalysisResult {
        try await analyzeAudioFile(at: url)
    }

    public func analyzeBeatGrid(audioSamples: [Float], sampleRate: Double, existingBPM: Double? = nil) async throws -> BeatGridDetector.BeatGrid {
        try await BeatGridDetector().detectBeatGrid(audioSamples: audioSamples, sampleRate: sampleRate, detectedBPM: existingBPM).beatGrid
    }

    /// Public for the regression runner: sample duration must agree with file duration.
    public func readAnalysisAudio(at url: URL) throws -> (samples: [Float], sampleRate: Double, duration: Double) {
        let file = try AVAudioFile(forReading: url)
        let rate = 22050.0
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration >= 2 else { throw failure("Audio is too short (minimum 2 seconds).") }
        // Budget includes analysis copies and envelopes, not just the mono buffer.
        guard duration * rate * 12 < Double(max(1, streamingConfig.maxMemoryMB)) * 1024 * 1024 else {
            throw failure("File exceeds the analysis memory budget. Split long recordings into tracks.")
        }
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32768),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 32768) else {
            throw failure("Unsupported audio format.")
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(duration * rate) + 32768)
        var readError: Error?
        while true {
            try Task.checkCancellation()
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
                guard file.framePosition < file.length else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    let remaining = AVAudioFrameCount(min(file.length - file.framePosition, AVAudioFramePosition(input.frameCapacity)))
                    try file.read(into: input, frameCount: min(requested, remaining))
                    inputStatus.pointee = input.frameLength == 0 ? .endOfStream : .haveData
                    return input.frameLength == 0 ? nil : input
                } catch where Self.isTailReadFailure(error, remaining: file.length - file.framePosition) {
                    // Some MP3s report a length about one packet longer than their decodable audio; the
                    // final short read then fails (eofErr, or no NSError at all). That is the end of the
                    // stream, not a broken file.
                    inputStatus.pointee = .endOfStream
                    return nil
                } catch {
                    readError = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let error = readError { throw error }
            if let error = conversionError { throw error }
            if output.frameLength > 0, let channel = output.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            if status == .endOfStream { break }
            if status == .error || output.frameLength == 0 { throw failure("Audio conversion produced no data.") }
        }
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }),
              samples.contains(where: { abs($0) > 0.00001 }) else {
            throw failure("No audible audio data was found.")
        }
        return (samples, rate, duration)
    }

    /// Core Audio's end-of-file status (OSStatus -39).
    public static let eofErr = -39
    /// Frames near the reported end where a failed read means end of stream (a few MP3 packets).
    public static let tailToleranceFrames: AVAudioFramePosition = 4608

    public static func isTailReadFailure(_ error: Error, remaining: AVAudioFramePosition) -> Bool {
        let status = error as NSError
        return (status.domain == NSOSStatusErrorDomain && status.code == eofErr) || remaining <= tailToleranceFrames
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "AudioProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
