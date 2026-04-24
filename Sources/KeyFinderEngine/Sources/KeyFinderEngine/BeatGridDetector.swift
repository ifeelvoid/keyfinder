import Foundation
import Accelerate

/// BeatGridDetector - Detects beat positions, phase, and downbeats for DJ use
/// Uses spectral flux for onset detection and autocorrelation for beat tracking
public class BeatGridDetector {

    // MARK: - Types

    public enum TimeSignature: Int, CaseIterable {
        case fourFour = 4   // 4/4 - most common in electronic/dance
        case threeFour = 3  // 3/4 - waltz time
        case sixEight = 6   // 6/8 - compound duple

        public var beatsPerBar: Int {
            return self.rawValue
        }
    }

    public struct Beat {
        public let time: TimeInterval      // Position in seconds
        public let strength: Float          // Beat strength (0-1)
        public let isDownbeat: Bool         // Is this beat 1 of the bar?
        public let beatNumber: Int          // 1, 2, 3, or 4 (within the bar)

        public init(time: TimeInterval, strength: Float, isDownbeat: Bool, beatNumber: Int) {
            self.time = time
            self.strength = strength
            self.isDownbeat = isDownbeat
            self.beatNumber = beatNumber
        }
    }

    public struct BeatGrid {
        public let beats: [Beat]            // All detected beats
        public let bpm: Double              // Tempo in beats per minute
        public let timeSignature: TimeSignature
        public let firstDownbeatTime: TimeInterval  // Position of first downbeat
        public let phase: Double            // Current phase (0.0 - 1.0) relative to downbeat

        public var beatsPerBar: Int {
            return timeSignature.beatsPerBar
        }

        /// Get the current beat number (1-4) at a given time position
        public func beatNumber(at time: TimeInterval) -> Int {
            guard !beats.isEmpty else { return 1 }

            // Find the most recent beat before or at the given time
            for beat in beats.reversed() {
                if beat.time <= time {
                    return beat.beatNumber
                }
            }
            return 1
        }

        /// Get the current phase (0.0-1.0) at a given time position
        public func phase(at time: TimeInterval) -> Double {
            guard !beats.isEmpty, let firstDownbeat = beats.first(where: { $0.isDownbeat }) else {
                return 0.0
            }

            let beatDuration = 60.0 / bpm
            let timeSinceDownbeat = time - firstDownbeat.time
            let beatsSinceDownbeat = timeSinceDownbeat / beatDuration

            return beatsSinceDownbeat.truncatingRemainder(dividingBy: 1.0)
        }

        /// Get the time until the next downbeat
        public func timeToNextDownbeat(from time: TimeInterval) -> TimeInterval {
            let barDuration = (60.0 / bpm) * Double(beatsPerBar)
            let timeSinceFirstDownbeat = time - firstDownbeatTime
            let barsSinceDownbeat = timeSinceFirstDownbeat / barDuration

            let currentBar = Int(barsSinceDownbeat)
            let nextDownbeatTime = firstDownbeatTime + Double(currentBar + 1) * barDuration

            return nextDownbeatTime - time
        }
    }

    public struct AnalysisOutput {
        public let beatGrid: BeatGrid
        public let onsetStrength: [Float]       // For visualization
        public let onsetTimes: [TimeInterval]    // When onsets occur

        public init(beatGrid: BeatGrid, onsetStrength: [Float], onsetTimes: [TimeInterval]) {
            self.beatGrid = beatGrid
            self.onsetStrength = onsetStrength
            self.onsetTimes = onsetTimes
        }
    }

    // MARK: - Configuration

    private let minBPM: Double = 60.0
    private let maxBPM: Double = 180.0
    private let fftSize = 2048
    private let hopSize = 512

    // MARK: - Public API

    /// Detect the complete beat grid for an audio file
    public func detectBeatGrid(audioSamples: [Float], sampleRate: Double, detectedBPM: Double? = nil) async throws -> AnalysisOutput {
        // Step 1: Calculate onset strength using spectral flux
        let onsetStrength = calculateOnsetStrength(samples: audioSamples, sampleRate: sampleRate)

        // Step 2: Get BPM (use provided or detect)
        let bpm = detectedBPM ?? detectBPMFromOnsets(onsetStrength: onsetStrength, sampleRate: sampleRate)

        // Step 3: Detect beats using adaptive threshold
        let beatTimes = detectBeatPositions(onsetStrength: onsetStrength, sampleRate: sampleRate, bpm: bpm)

        // Step 4: Detect time signature and downbeats
        let (timeSignature, beats) = detectDownbeatsAndPhase(
            beatTimes: beatTimes,
            onsetStrength: onsetStrength,
            sampleRate: sampleRate,
            bpm: bpm,
            audioSamples: audioSamples
        )

        // Get onset times for visualization
        let onsetTimes = getOnsetTimes(onsetStrength: onsetStrength, sampleRate: sampleRate)

        // Calculate first downbeat time
        let firstDownbeatTime = beats.first(where: { $0.isDownbeat })?.time ?? 0.0

        let beatGrid = BeatGrid(
            beats: beats,
            bpm: bpm,
            timeSignature: timeSignature,
            firstDownbeatTime: firstDownbeatTime,
            phase: 0.0
        )

        return AnalysisOutput(
            beatGrid: beatGrid,
            onsetStrength: onsetStrength,
            onsetTimes: onsetTimes
        )
    }

    /// Get phase at a specific time position
    public func getPhase(at time: TimeInterval, beatGrid: BeatGrid) -> Double {
        return beatGrid.phase(at: time)
    }

    /// Get beat number (1-4) at a specific time position
    public func getBeatNumber(at time: TimeInterval, beatGrid: BeatGrid) -> Int {
        return beatGrid.beatNumber(at: time)
    }

    // MARK: - Private Implementation

    /// Calculate spectral flux for onset detection
    private func calculateOnsetStrength(samples: [Float], sampleRate: Double) -> [Float] {
        var onsetStrength = [Float]()
        var previousSpectrum = [Float](repeating: 0.0, count: fftSize / 2)

        for frameStart in stride(from: 0, to: samples.count - fftSize, by: hopSize) {
            let frameEnd = min(frameStart + fftSize, samples.count)
            let frame = Array(samples[frameStart..<frameEnd])

            // Apply Hann window
            let windowedFrame = applyHannWindow(frame)

            // Get magnitude spectrum
            let spectrum = performFFT(windowedFrame)

            // Calculate spectral flux (half-wave rectified difference)
            var flux: Float = 0.0
            for i in 0..<spectrum.count {
                let diff = spectrum[i] - previousSpectrum[i]
                flux += max(0, diff) // Half-wave rectification - only positive changes
            }

            onsetStrength.append(flux)
            previousSpectrum = spectrum
        }

        // Normalize
        if let maxFlux = onsetStrength.max(), maxFlux > 0 {
            onsetStrength = onsetStrength.map { $0 / maxFlux }
        }

        return onsetStrength
    }

    /// Apply Hann window to samples
    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        let n = samples.count
        return samples.enumerated().map { index, sample in
            let window = 0.5 - 0.5 * cos(2.0 * .pi * Double(index) / Double(n - 1))
            return sample * Float(window)
        }
    }

    /// Perform FFT and return magnitude spectrum
    private func performFFT(_ samples: [Float]) -> [Float] {
        var real = samples
        var imaginary = [Float](repeating: 0.0, count: fftSize)

        // Pad if necessary
        while real.count < fftSize {
            real.append(0.0)
        }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else {
            return [Float](repeating: 0.0, count: fftSize / 2)
        }

        var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imaginary.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        vDSP_destroy_fftsetup(fftSetup)

        return magnitudes
    }

    /// Detect BPM from onset strength using autocorrelation
    private func detectBPMFromOnsets(onsetStrength: [Float], sampleRate: Double) -> Double {
        let framesPerSecond = sampleRate / Double(hopSize)

        // Calculate onset autocorrelation (tempogram)
        let tempogram = calculateAutocorrelation(onsetStrength)

        // Find peaks in the BPM range
        let minLag = Int(60.0 / maxBPM * framesPerSecond)
        let maxLag = min(Int(60.0 / minBPM * framesPerSecond), tempogram.count - 1)

        var maxPeak: Float = 0.0
        var maxPeakLag = minLag

        for lag in minLag...maxLag {
            if tempogram[lag] > maxPeak {
                // Check if local maximum
                if lag > 0 && lag < tempogram.count - 1 {
                    if tempogram[lag] > tempogram[lag - 1] &&
                       tempogram[lag] > tempogram[lag + 1] {
                        maxPeak = tempogram[lag]
                        maxPeakLag = lag
                    }
                }
            }
        }

        let bpm = 60.0 * framesPerSecond / Double(maxPeakLag)
        return max(60.0, min(180.0, round(bpm * 10) / 10))
    }

    /// Calculate autocorrelation of onset signal
    private func calculateAutocorrelation(_ signal: [Float]) -> [Float] {
        let n = signal.count
        var autocorrelation = [Float](repeating: 0.0, count: n)

        // Use Accelerate for faster computation
        var sum: Float = 0.0
        vDSP_dotpr(signal, 1, signal, 1, &sum, vDSP_Length(n))
        autocorrelation[0] = sum

        for lag in 1..<min(n, 10000) { // Limit lag for performance
            var lagSum: Float = 0.0
            let count = vDSP_Length(n - lag)
            vDSP_dotpr(signal, 1, Array(signal[lag..<n]), 1, &lagSum, count)
            autocorrelation[lag] = lagSum
        }

        return autocorrelation
    }

    /// Detect beat positions using adaptive threshold
    private func detectBeatPositions(onsetStrength: [Float], sampleRate: Double, bpm: Double) -> [TimeInterval] {
        let framesPerSecond = sampleRate / Double(hopSize)
        let beatInterval = 60.0 / bpm
        let beatFrameInterval = beatInterval * framesPerSecond

        // Use adaptive thresholding
        let windowSize = Int(beatFrameInterval * 2) // Window covers ~2 beats
        var thresholdedBeats: [Int] = []

        for i in 0..<onsetStrength.count {
            // Calculate local mean in window
            let windowStart = max(0, i - windowSize / 2)
            let windowEnd = min(onsetStrength.count, i + windowSize / 2)
            let window = Array(onsetStrength[windowStart..<windowEnd])

            let localMean = window.reduce(0, +) / Float(window.count)
            let adaptiveThreshold = localMean * 1.3 + 0.05 // 30% above mean + minimum

            // Check if this is a local maximum above threshold
            if onsetStrength[i] > adaptiveThreshold {
                // Check if local maximum
                if i > 0 && i < onsetStrength.count - 1 {
                    if onsetStrength[i] > onsetStrength[i - 1] &&
                       onsetStrength[i] > onsetStrength[i + 1] {
                        thresholdedBeats.append(i)
                    }
                }
            }
        }

        // Convert frame indices to time
        var beatTimes = thresholdedBeats.map { TimeInterval($0) / framesPerSecond }

        // Filter out beats that are too close together (minimum 200ms apart)
        beatTimes = filterCloseBeats(beatTimes, minimumInterval: 0.2)

        return beatTimes
    }

    /// Filter out beats that are too close together
    private func filterCloseBeats(_ beats: [TimeInterval], minimumInterval: TimeInterval) -> [TimeInterval] {
        guard !beats.isEmpty else { return [] }

        var filtered: [TimeInterval] = [beats[0]]

        for i in 1..<beats.count {
            if beats[i] - filtered.last! >= minimumInterval {
                filtered.append(beats[i])
            }
        }

        return filtered
    }

    /// Detect downbeats using low-frequency energy analysis
    private func detectDownbeatsAndPhase(
        beatTimes: [TimeInterval],
        onsetStrength: [Float],
        sampleRate: Double,
        bpm: Double,
        audioSamples: [Float]
    ) -> (TimeSignature, [Beat]) {
        let beatsPerBar = detectTimeSignature(beatTimes: beatTimes, bpm: bpm)
        let timeSignature = TimeSignature(rawValue: beatsPerBar) ?? .fourFour

        // Calculate beat strength based on low-frequency energy
        let beatStrengths = calculateBeatStrengths(
            beatTimes: beatTimes,
            audioSamples: audioSamples,
            sampleRate: sampleRate
        )

        // Create beat objects with downbeat markers
        var beats: [Beat] = []

        // Estimate the first downbeat position
        let firstDownbeatEstimate = findFirstDownbeat(
            beatTimes: beatTimes,
            beatStrengths: beatStrengths,
            beatsPerBar: beatsPerBar
        )

        // Assign beat numbers
        let beatDuration = 60.0 / bpm
        _ = beatDuration // Used for beat number calculation below

        for (index, beatTime) in beatTimes.enumerated() {
            let isDownbeat: Bool
            let beatNum: Int

            if index == 0 {
                // First detected beat - treat as potential downbeat
                isDownbeat = true
                beatNum = 1
            } else {
                // Calculate beat number based on time from first downbeat
                let timeSinceFirst = beatTime - firstDownbeatEstimate
                let beatsFromFirst = Int(round(timeSinceFirst / beatDuration))
                beatNum = ((beatsFromFirst % beatsPerBar) + beatsPerBar + 1) % beatsPerBar + 1
                isDownbeat = (beatNum == 1)
            }

            let strength = index < beatStrengths.count ? beatStrengths[index] : 0.5

            beats.append(Beat(
                time: beatTime,
                strength: strength,
                isDownbeat: isDownbeat,
                beatNumber: beatNum
            ))
        }

        return (timeSignature, beats)
    }

    /// Detect time signature from beat pattern
    private func detectTimeSignature(beatTimes: [TimeInterval], bpm: Double) -> Int {
        guard beatTimes.count >= 8 else { return 4 }

        // Calculate average intervals
        var intervals: [TimeInterval] = []
        for i in 1..<beatTimes.count {
            intervals.append(beatTimes[i] - beatTimes[i - 1])
        }

        let expectedBeatInterval = 60.0 / bpm

        // Look for patterns in intervals (group into bars)
        var barLengths: [Int] = []

        // Count intervals that are approximately 2x or 3x the beat duration
        for interval in intervals {
            let ratio = interval / expectedBeatInterval
            if ratio > 1.7 && ratio < 2.3 {
                barLengths.append(2) // Likely 2 beats = 1 bar in 4/4
            } else if ratio > 2.7 && ratio < 3.3 {
                barLengths.append(3) // Likely 3 beats = 1 bar in 3/4
            } else if ratio > 5.5 && ratio < 6.5 {
                barLengths.append(6) // Likely 6 beats = 2 bars in 6/8
            }
        }

        // Determine most common pattern
        let twoBeats = barLengths.filter { $0 == 2 }.count
        let threeBeats = barLengths.filter { $0 == 3 }.count
        let sixBeats = barLengths.filter { $0 == 6 }.count

        if sixBeats > twoBeats && sixBeats > threeBeats {
            return 6 // 6/8
        } else if threeBeats > twoBeats && threeBeats > 0 {
            return 3 // 3/4
        }

        return 4 // Default to 4/4
    }

    /// Calculate strength for each beat based on low-frequency energy
    private func calculateBeatStrengths(
        beatTimes: [TimeInterval],
        audioSamples: [Float],
        sampleRate: Double
    ) -> [Float] {
        // For efficiency, sample low-frequency energy at beat positions
        let fftSize = 4096 // Larger window for better bass resolution

        var strengths: [Float] = []

        for beatTime in beatTimes {
            let sampleIndex = Int(beatTime * sampleRate)
            let startSample = max(0, sampleIndex - fftSize / 2)
            let endSample = min(audioSamples.count, sampleIndex + fftSize / 2)

            guard endSample > startSample else {
                strengths.append(0.5)
                continue
            }

            let frame = Array(audioSamples[startSample..<endSample])
            let windowedFrame = applyHannWindow(frame)

            // Calculate low-frequency energy (first 1/8 of spectrum)
            let spectrum = performFFT_Large(windowedFrame)
            let lowFreqBins = spectrum.count / 8

            var lowFreqEnergy: Float = 0
            for i in 0..<lowFreqBins {
                lowFreqEnergy += spectrum[i] * spectrum[i]
            }
            lowFreqEnergy /= Float(lowFreqBins)

            strengths.append(min(1.0, lowFreqEnergy / 1000.0))
        }

        // Normalize
        if let maxStrength = strengths.max(), maxStrength > 0 {
            strengths = strengths.map { $0 / maxStrength }
        }

        return strengths
    }

    /// Perform FFT with larger size
    private func performFFT_Large(_ samples: [Float]) -> [Float] {
        let fftSize = 4096

        var real = samples
        var imaginary = [Float](repeating: 0.0, count: fftSize)

        while real.count < fftSize {
            real.append(0.0)
        }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else {
            return [Float](repeating: 0.0, count: fftSize / 2)
        }

        var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imaginary.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        vDSP_destroy_fftsetup(fftSetup)

        return magnitudes
    }

    /// Find the first downbeat by analyzing beat strength patterns
    private func findFirstDownbeat(
        beatTimes: [TimeInterval],
        beatStrengths: [Float],
        beatsPerBar: Int
    ) -> TimeInterval {
        guard beatTimes.count >= beatsPerBar else {
            return beatTimes.first ?? 0
        }

        // Look for patterns where one beat is stronger (likely downbeat)
        // Analyze groups of beatsPerBar beats
        var candidates: [(offset: Int, score: Float)] = []

        for offset in 0..<min(beatsPerBar, beatTimes.count) {
            var score: Float = 0
            var count = 0

            for i in stride(from: offset, to: beatStrengths.count, by: beatsPerBar) {
                if i < beatStrengths.count {
                    score += beatStrengths[i]
                    count += 1
                }
            }

            if count > 0 {
                candidates.append((offset, score / Float(count)))
            }
        }

        // Choose the offset with highest average strength (likely downbeat)
        if let best = candidates.max(by: { $0.score < $1.score }) {
            return beatTimes[best.offset]
        }

        return beatTimes.first ?? 0
    }

    /// Get onset times for visualization
    private func getOnsetTimes(onsetStrength: [Float], sampleRate: Double) -> [TimeInterval] {
        let framesPerSecond = sampleRate / Double(hopSize)
        var onsetTimes: [TimeInterval] = []

        // Find peaks in onset strength
        for i in 1..<(onsetStrength.count - 1) {
            if onsetStrength[i] > onsetStrength[i - 1] &&
               onsetStrength[i] > onsetStrength[i + 1] &&
               onsetStrength[i] > 0.3 { // Threshold
                onsetTimes.append(TimeInterval(i) / framesPerSecond)
            }
        }

        return onsetTimes
    }
}