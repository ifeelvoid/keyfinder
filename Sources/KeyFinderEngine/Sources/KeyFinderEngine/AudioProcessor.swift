import Foundation
import AVFoundation

// MARK: - Streaming Audio Processor
/// Memory-efficient audio processor that handles large files without loading everything into memory
public class AudioProcessor {
    private let keyDetector = KeyDetector()
    private let bpmDetector = BPMDetector()
    private let beatGridDetector = BeatGridDetector()

    public enum EnergyLevel: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case veryHigh = "Very High"
    }

    public struct AnalysisResult {
        public let key: KeyDetector.MusicalKey
        public let bpm: Double
        public let fileName: String
        public let confidence: Double
        public let keyChanges: [(TimeInterval, KeyDetector.MusicalKey, Double)]
        public let duration: TimeInterval
        public let energy: EnergyLevel
        public let beatGrid: BeatGridDetector.BeatGrid?

        public init(key: KeyDetector.MusicalKey, bpm: Double, fileName: String, confidence: Double, keyChanges: [(TimeInterval, KeyDetector.MusicalKey, Double)], duration: TimeInterval, energy: EnergyLevel, beatGrid: BeatGridDetector.BeatGrid?) {
            self.key = key
            self.bpm = bpm
            self.fileName = fileName
            self.confidence = confidence
            self.keyChanges = keyChanges
            self.duration = duration
            self.energy = energy
            self.beatGrid = beatGrid
        }
    }

    // MARK: - Streaming Analysis Configuration
    public struct StreamingConfig {
        public let chunkDuration: TimeInterval // Duration of each audio chunk in seconds
        public let overlap: TimeInterval // Overlap between chunks for smooth analysis
        public let maxMemoryMB: Int // Maximum memory to use

        public static let `default` = StreamingConfig(
            chunkDuration: 30.0,
            overlap: 5.0,
            maxMemoryMB: 512
        )

        public static let lowMemory = StreamingConfig(
            chunkDuration: 15.0,
            overlap: 2.0,
            maxMemoryMB: 256
        )

        public init(chunkDuration: TimeInterval, overlap: TimeInterval, maxMemoryMB: Int) {
            self.chunkDuration = chunkDuration
            self.overlap = overlap
            self.maxMemoryMB = maxMemoryMB
        }
    }

    private var streamingConfig: StreamingConfig = .default

    public init() {}

    public func analyzeAudioFile(at url: URL) async throws -> AnalysisResult {
        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let duration = Double(audioFile.length) / sampleRate

        // For files longer than 3 minutes, use smart sampling for faster analysis
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let shouldDownsample = duration > 180 // 3 minutes

        let samples: [Float]
        if shouldDownsample {
            // Sample every 3rd second for long files (still accurate for key/BPM)
            samples = try extractDownsampledMono(from: audioFile, totalFrames: totalFrames)
        } else {
            // Load full file for shorter tracks
            let frameCount = UInt32(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw NSError(domain: "AudioProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
            }
            try audioFile.read(into: buffer)
            samples = extractMonoSamples(from: buffer)
        }

        // Perform analysis with key change detection
        async let keyResult = keyDetector.detectKeyWithChanges(audioSamples: samples, sampleRate: sampleRate)
        async let bpm = bpmDetector.detectBPM(audioSamples: samples, sampleRate: sampleRate)
        async let beatGrid = beatGridDetector.detectBeatGrid(audioSamples: samples, sampleRate: sampleRate, detectedBPM: nil)

        let (detectedKey, confidence, keyChanges) = try await keyResult
        let detectedBPM = try await bpm
        let detectedBeatGrid = try await beatGrid

        // Analyze energy level (fast approximation)
        let energy = analyzeEnergyFast(samples: samples, sampleRate: sampleRate)

        return AnalysisResult(
            key: detectedKey,
            bpm: detectedBPM,
            fileName: url.lastPathComponent,
            confidence: confidence,
            keyChanges: keyChanges,
            duration: duration,
            energy: energy,
            beatGrid: detectedBeatGrid.beatGrid
        )
    }

    /// Analyze only beatgrid (for faster updates when BPM is already known)
    public func analyzeBeatGrid(audioSamples: [Float], sampleRate: Double, existingBPM: Double? = nil) async throws -> BeatGridDetector.BeatGrid {
        let result = try await beatGridDetector.detectBeatGrid(
            audioSamples: audioSamples,
            sampleRate: sampleRate,
            detectedBPM: existingBPM
        )
        return result.beatGrid
    }

    /// Configure streaming mode for large file handling
    public func setStreamingMode(config: StreamingConfig) {
        self.streamingConfig = config
    }

    /// Analyze audio file using streaming mode for very large files (>10 minutes)
    /// This processes audio in chunks to minimize memory usage
    public func analyzeAudioFileStreaming(at url: URL) async throws -> AnalysisResult {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let duration = Double(audioFile.length) / sampleRate
        let totalFrames = AVAudioFrameCount(audioFile.length)

        // Determine if we need streaming based on file size and memory constraints
        let estimatedMemory = PerformanceUtils.estimateMemoryUsage(
            sampleCount: Int(totalFrames),
            fftSize: PerformanceUtils.recommendedFFTSize()
        )

        // Use downsampling for very large files (>10 minutes or high memory usage)
        if duration > 600 || estimatedMemory > Int64(streamingConfig.maxMemoryMB) * 1024 * 1024 {
            // Re-open the file since analyzeWithDownsampling needs a fresh file handle
            let newAudioFile = try AVAudioFile(forReading: url)
            return try await analyzeWithDownsampling(url: url, audioFile: newAudioFile, duration: duration, sampleRate: sampleRate)
        }

        return try await analyzeAudioFile(at: url)
    }

    /// Internal method for downsampled analysis with memory management
    private func analyzeWithDownsampling(url: URL, audioFile: AVAudioFile, duration: TimeInterval, sampleRate: Double) async throws -> AnalysisResult {
        // Extract samples with autoreleasepool for memory efficiency
        let samples = try await Task {
            return try self.extractDownsampledMono(from: audioFile, totalFrames: AVAudioFrameCount(audioFile.length))
        }.value

        // Perform analysis
        async let keyResult = keyDetector.detectKeyWithChanges(audioSamples: samples, sampleRate: sampleRate)
        async let bpm = bpmDetector.detectBPM(audioSamples: samples, sampleRate: sampleRate)
        async let beatGrid = beatGridDetector.detectBeatGrid(audioSamples: samples, sampleRate: sampleRate, detectedBPM: nil)

        let (detectedKey, confidence, keyChanges) = try await keyResult
        let detectedBPM = try await bpm
        let detectedBeatGrid = try await beatGrid
        let energy = analyzeEnergyFast(samples: samples, sampleRate: sampleRate)

        return AnalysisResult(
            key: detectedKey,
            bpm: detectedBPM,
            fileName: url.lastPathComponent,
            confidence: confidence,
            keyChanges: keyChanges,
            duration: duration,
            energy: energy,
            beatGrid: detectedBeatGrid.beatGrid
        )
    }

    private func extractDownsampledMono(from audioFile: AVAudioFile, totalFrames: AVAudioFrameCount) throws -> [Float] {
        let format = audioFile.processingFormat
        let chunkSize: AVAudioFrameCount = 44100 // 1 second chunks
        let skipFrames: AVAudioFrameCount = 88200 // Skip 2 seconds between sample

        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(totalFrames / 3)) // Approximate size

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw NSError(domain: "AudioProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        var currentFrame: AVAudioFramePosition = 0

        while currentFrame < AVAudioFramePosition(totalFrames) {
            autoreleasepool {
                audioFile.framePosition = currentFrame

                let remainingFrames = AVAudioFramePosition(totalFrames) - currentFrame
                let framesToRead = min(AVAudioFrameCount(chunkSize), AVAudioFrameCount(remainingFrames))
                try? audioFile.read(into: buffer, frameCount: framesToRead)

                let chunkSamples = extractMonoSamples(from: buffer)
                allSamples.append(contentsOf: chunkSamples)

                currentFrame += AVAudioFramePosition(chunkSize + skipFrames)
            }
        }

        return allSamples
    }

    private func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let floatData = buffer.floatChannelData else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var monoSamples = [Float](repeating: 0.0, count: frameLength)

        if channelCount == 1 {
            // Already mono
            monoSamples = Array(UnsafeBufferPointer(start: floatData[0], count: frameLength))
        } else {
            // Convert to mono by averaging channels
            for frame in 0..<frameLength {
                var sum: Float = 0.0
                for channel in 0..<channelCount {
                    sum += floatData[channel][frame]
                }
                monoSamples[frame] = sum / Float(channelCount)
            }
        }

        return monoSamples
    }

    private func analyzeEnergy(samples: [Float], sampleRate: Double) -> EnergyLevel {
        // Calculate RMS energy over the entire track
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))

        // Calculate spectral energy (higher frequencies = more energy)
        let windowSize = 2048
        var spectralEnergy: Float = 0
        var windowCount = 0

        for i in stride(from: 0, to: samples.count - windowSize, by: windowSize / 2) {
            let window = Array(samples[i..<min(i + windowSize, samples.count)])
            let fft = performSimpleFFT(window)

            // Weight higher frequencies more
            for (index, magnitude) in fft.enumerated() {
                let frequencyWeight = Float(index) / Float(fft.count)
                spectralEnergy += magnitude * frequencyWeight
            }
            windowCount += 1
        }

        spectralEnergy /= Float(windowCount)

        // Combine RMS and spectral energy
        let totalEnergy = (rms * 0.6) + (spectralEnergy * 0.4)

        // Classify energy level
        if totalEnergy > 0.15 {
            return .veryHigh
        } else if totalEnergy > 0.08 {
            return .high
        } else if totalEnergy > 0.04 {
            return .medium
        } else {
            return .low
        }
    }

    private func analyzeEnergyFast(samples: [Float], sampleRate: Double) -> EnergyLevel {
        // Fast energy calculation - just RMS, skip spectral analysis
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))

        // Simplified thresholds based on RMS only
        if rms > 0.12 {
            return .veryHigh
        } else if rms > 0.07 {
            return .high
        } else if rms > 0.03 {
            return .medium
        } else {
            return .low
        }
    }

    private func performSimpleFFT(_ samples: [Float]) -> [Float] {
        // Simple magnitude calculation for energy analysis
        var magnitudes: [Float] = []
        let windowSize = samples.count

        for k in 0..<(windowSize / 2) {
            var real: Float = 0
            var imag: Float = 0

            for n in 0..<windowSize {
                let angle = -2.0 * Float.pi * Float(k) * Float(n) / Float(windowSize)
                real += samples[n] * cos(angle)
                imag += samples[n] * sin(angle)
            }

            let magnitude = sqrt(real * real + imag * imag)
            magnitudes.append(magnitude)
        }

        return magnitudes
    }
}

// MARK: - Performance Utils
struct PerformanceUtils {
    static func estimateMemoryUsage(sampleCount: Int, fftSize: Int) -> Int64 {
        // Rough estimate: each sample is 4 bytes (Float32)
        // FFT uses ~3x the fftSize in working memory
        let sampleMemory = Int64(sampleCount) * 4
        let fftMemory = Int64(fftSize) * 4 * 3
        return sampleMemory + fftMemory
    }

    static func recommendedFFTSize() -> Int {
        return 32768
    }
}