import Foundation
import Accelerate

public class KeyDetector {
    // Development-only GiantSteps+ v2 profiles: 50% empirical median / 50% normalized KS.
    // Coefficients, contributor hashes and dataset attribution are recorded in
    // docs/briefs/0004-public-key-challenge/profile-provenance.json.
    // EDM-specific: 24 major and 206 minor examples; extraction and scoring are unchanged.
    private static let majorProfile: [Double] = [
        0.1275930110697475, 0.0623281238962653, 0.0856139951706759, 0.062434445057663025,
        0.10059235106369269, 0.08946810513660708, 0.06685370853481933, 0.11450725102532114,
        0.06293247226287722, 0.08759937643779363, 0.061632033039242085, 0.07844512730529522
    ]
    private static let minorProfile: [Double] = [
        0.12295831518055632, 0.06713257770803258, 0.08267739330362738, 0.10456108651196024,
        0.06793500512433348, 0.08110914848416328, 0.06509663723126663, 0.10267883579369759,
        0.08369819182992237, 0.06756749780032058, 0.0806585670113963, 0.07392674402072341
    ]

    /// Experimental chroma weighting modes for brief #0005. `.baseline` is production behaviour.
    public enum SpectralMode: String, CaseIterable {
        case baseline
        /// W: peak magnitude divided by the mean magnitude of its one-third-octave neighbourhood.
        case whitened
        /// WH: W plus HPCP-style subharmonic contributions (h = 2...4, decay 0.6).
        case whitenedHarmonic
    }

    private static let harmonicCount = 4
    private static let harmonicDecay = 0.6

    public let spectralMode: SpectralMode
    /// Template set: EDM = learned50 (GiantSteps+), Trap / Hip-Hop = catalog-fitted minor (#0010).
    public let style: KeyStyle
    /// Template correlation or the #0010 key-equivariant model.
    public let method: KeyMethod

    public init(spectralMode: SpectralMode = .baseline, style: KeyStyle = .edm, method: KeyMethod = .templates) {
        self.spectralMode = spectralMode
        self.style = style
        self.method = method
    }

    public enum MusicalKey: String, CaseIterable {
        case cMajor = "C Major", cSharpMajor = "C# Major", dMajor = "D Major"
        case dSharpMajor = "D# Major", eMajor = "E Major", fMajor = "F Major"
        case fSharpMajor = "F# Major", gMajor = "G Major", gSharpMajor = "G# Major"
        case aMajor = "A Major", aSharpMajor = "A# Major", bMajor = "B Major"
        case cMinor = "C Minor", cSharpMinor = "C# Minor", dMinor = "D Minor"
        case dSharpMinor = "D# Minor", eMinor = "E Minor", fMinor = "F Minor"
        case fSharpMinor = "F# Minor", gMinor = "G Minor", gSharpMinor = "G# Minor"
        case aMinor = "A Minor", aSharpMinor = "A# Minor", bMinor = "B Minor"

        public var camelotNotation: String {
            switch self {
            case .cMajor: return "8B"
            case .cSharpMajor: return "3B"
            case .dMajor: return "10B"
            case .dSharpMajor: return "5B"
            case .eMajor: return "12B"
            case .fMajor: return "7B"
            case .fSharpMajor: return "2B"
            case .gMajor: return "9B"
            case .gSharpMajor: return "4B"
            case .aMajor: return "11B"
            case .aSharpMajor: return "6B"
            case .bMajor: return "1B"
            case .cMinor: return "5A"
            case .cSharpMinor: return "12A"
            case .dMinor: return "7A"
            case .dSharpMinor: return "2A"
            case .eMinor: return "9A"
            case .fMinor: return "4A"
            case .fSharpMinor: return "11A"
            case .gMinor: return "6A"
            case .gSharpMinor: return "1A"
            case .aMinor: return "8A"
            case .aSharpMinor: return "3A"
            case .bMinor: return "10A"
            }
        }

        public var shortName: String {
            switch self {
            case .cMajor: return "C"
            case .cSharpMajor: return "C#"
            case .dMajor: return "D"
            case .dSharpMajor: return "D#"
            case .eMajor: return "E"
            case .fMajor: return "F"
            case .fSharpMajor: return "F#"
            case .gMajor: return "G"
            case .gSharpMajor: return "G#"
            case .aMajor: return "A"
            case .aSharpMajor: return "A#"
            case .bMajor: return "B"
            case .cMinor: return "Cm"
            case .cSharpMinor: return "C#m"
            case .dMinor: return "Dm"
            case .dSharpMinor: return "D#m"
            case .eMinor: return "Em"
            case .fMinor: return "Fm"
            case .fSharpMinor: return "F#m"
            case .gMinor: return "Gm"
            case .gSharpMinor: return "G#m"
            case .aMinor: return "Am"
            case .aSharpMinor: return "A#m"
            case .bMinor: return "Bm"
            }
        }
    }

    public func detectKey(audioSamples: [Float], sampleRate: Double) async throws -> MusicalKey {
        let (key, _) = try await detectKeyWithConfidence(audioSamples: audioSamples, sampleRate: sampleRate)
        return key
    }

    public func detectKeyWithConfidence(audioSamples: [Float], sampleRate: Double) async throws -> (MusicalKey, Double) {
        let (key, confidence, _) = try await detectKeyWithChanges(audioSamples: audioSamples, sampleRate: sampleRate)
        return (key, confidence)
    }

    public enum AnalysisError: Error, LocalizedError {
        case invalidSampleRate, invalidSamples, insufficientAudio, noTonalEvidence

        public var errorDescription: String? {
            switch self {
            case .invalidSampleRate: return "Key analysis requires a finite sample rate between 4 and 192 kHz."
            case .invalidSamples: return "Key analysis requires finite audio samples."
            case .insufficientAudio: return "Key analysis requires at least 4096 audio samples."
            case .noTonalEvidence: return "No usable tonal evidence was found in this audio."
            }
        }
    }

    private struct SegmentEvidence {
        let scores: [(MusicalKey, Double)]
        let weight: Double
        let timestamp: TimeInterval
    }

    /// Uncompressed, normalized pitch-class evidence used by the key detector.
    /// RMS refers to samples normalized by the recording's largest absolute sample.
    public struct TonalSegment: Codable {
        public let chroma: [Double]
        public let rms: Double
        public let timestamp: Double
        /// Normalized semitone evidence over MIDI 33...104 (72 bins); nil in legacy exports.
        public let pitch: [Double]?
    }

    /// Lowest MIDI note and bin count of the semitone feature used by the key model.
    public static let pitchFeatureLowestNote = 33
    public static let pitchFeatureBins = 72

    private struct ToneEvidence {
        let chroma: [Double]
        let pitch: [Double]
    }

    public func collectTonalEvidence(audioSamples: [Float], sampleRate: Double) async throws -> [TonalSegment] {
        try Task.checkCancellation()
        guard sampleRate.isFinite, (4000...192000).contains(sampleRate) else { throw AnalysisError.invalidSampleRate }
        guard audioSamples.count >= 4096 else { throw AnalysisError.insufficientAudio }
        var peak = 0.0
        for (index, sample) in audioSamples.enumerated() {
            if index % 65536 == 0 { try Task.checkCancellation() }
            guard sample.isFinite else { throw AnalysisError.invalidSamples }
            peak = max(peak, abs(Double(sample)))
        }
        guard peak > 0 else { throw AnalysisError.noTonalEvidence }

        let segmentLength = min(audioSamples.count, Int(sampleRate * 30))
        let segmentCount = audioSamples.count <= segmentLength ? 1 : 5
        var segments: [TonalSegment] = []
        for index in 0..<segmentCount {
            try Task.checkCancellation()
            let start = segmentCount == 1 ? 0 : (audioSamples.count - segmentLength) * index / (segmentCount - 1)
            // Normalize before FFT to avoid overflow and make global gain irrelevant.
            let samples = audioSamples[start..<(start + segmentLength)].map { Float(Double($0) / peak) }
            let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
            guard rms > 1e-8 else { continue }
            let tone = try await calculateChromagram(samples: samples, sampleRate: sampleRate)
            guard tone.chroma.reduce(0, +) > 0 else { continue }
            segments.append(TonalSegment(chroma: tone.chroma, rms: rms, timestamp: Double(start) / sampleRate,
                                         pitch: tone.pitch))
        }
        guard !segments.isEmpty else { throw AnalysisError.noTonalEvidence }
        return segments
    }

    /// Confidence measures separation and agreement of tonal evidence; it is not an accuracy probability.
    public func detectKeyWithChanges(audioSamples: [Float], sampleRate: Double) async throws -> (MusicalKey, Double, [(TimeInterval, MusicalKey, Double)]) {
        let segments = try await collectTonalEvidence(audioSamples: audioSamples, sampleRate: sampleRate)
        if method == .model, let modelResult = modelDetection(segments: segments) { return modelResult }
        var evidence: [SegmentEvidence] = []
        for segment in segments {
            let scores = correlateWithKeyProfiles(chromagram: segment.chroma, returnTopN: 24)
            guard let top = scores.first, top.1 > 0 else { continue }
            evidence.append(SegmentEvidence(scores: scores, weight: sqrt(segment.rms) * top.1,
                                            timestamp: segment.timestamp))
        }
        guard !evidence.isEmpty else { throw AnalysisError.noTonalEvidence }

        // Retain competing candidates. Winner-only votes used to erase within-segment ambiguity.
        let keys = MusicalKey.allCases
        var votes = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0.0) })
        var totalWeight = 0.0
        for segment in evidence {
            let best = segment.scores[0].1
            let weights = segment.scores.map { exp(8 * ($0.1 - best)) }
            let sum = weights.reduce(0, +)
            for (candidate, weight) in zip(segment.scores, weights) {
                votes[candidate.0, default: 0] += weight / sum * segment.weight
            }
            totalWeight += segment.weight
        }
        let ranked = keys.sorted {
            let left = votes[$0, default: 0], right = votes[$1, default: 0]
            return left == right ? $0.rawValue < $1.rawValue : left > right
        }
        let key = ranked[0]
        let first = votes[key, default: 0]
        let second = votes[ranked[1], default: 0]
        let separation = first > 0 ? 1 - second / first : 0
        let quality = evidence.reduce(0.0) { sum, segment in
            sum + max(0, segment.scores.first(where: { $0.0 == key })!.1) * segment.weight
        } / totalWeight
        let agreement = evidence.filter { $0.scores[0].0 == key }.reduce(0) { $0 + $1.weight } / totalWeight
        let confidence = min(1, max(0, separation * quality * (0.75 + 0.25 * agreement)))

        // Preserve genuine differing segments instead of discarding them as majority outliers.
        var changes: [(TimeInterval, MusicalKey, Double)] = []
        for segment in evidence {
            let winner = segment.scores[0]
            if changes.last?.1 != winner.0 {
                let runnerUp = segment.scores[1].1
                let certainty = max(0, winner.1) * (1 - exp(8 * (runnerUp - winner.1)))
                changes.append((segment.timestamp, winner.0, min(1, max(0, certainty))))
            }
        }
        return (key, confidence, changes)
    }

    private struct SpectralPeak {
        let pitch: Double // MIDI pitch, including fractional tuning offset
        let magnitude: Double
        let chromaWeight: Double // equals magnitude in baseline mode
    }

    /// Prefix sums of a magnitude spectrum, for one-third-octave local means.
    private static func prefixSums(_ spectrum: [Float]) -> [Double] {
        var sums = [Double](repeating: 0, count: spectrum.count + 1)
        for index in spectrum.indices { sums[index + 1] = sums[index] + Double(spectrum[index]) }
        return sums
    }

    private static func localMean(bin: Int, prefix: [Double]) -> Double {
        let lower = max(0, Int(floor(Double(bin) * pow(2, -1.0 / 6))))
        let upper = min(prefix.count - 2, Int(ceil(Double(bin) * pow(2, 1.0 / 6))))
        return (prefix[upper + 1] - prefix[lower]) / Double(upper - lower + 1)
    }

    private func calculateChromagram(samples: [Float], sampleRate: Double) async throws -> ToneEvidence {
        let fftSize = [32768, 16384, 8192, 4096].first { $0 <= samples.count }!
        let hopSize = fftSize / 8
        let window = WindowCache.shared.getHannWindow(size: fftSize) ?? {
            var values = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&values, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            return values
        }()
        let lastStart = samples.count - fftSize
        var starts = Array(stride(from: 0, through: lastStart, by: hopSize))
        if starts.last != lastStart { starts.append(lastStart) }
        var frames: [[SpectralPeak]] = []
        var tuningCos = 0.0, tuningSin = 0.0, tuningWeight = 0.0
        let firstBin = max(2, Int(55 * Double(fftSize) / sampleRate))
        let lastBin = min(fftSize / 2 - 2, Int(min(5512.5, sampleRate / 2) * Double(fftSize) / sampleRate))
        guard firstBin <= lastBin else {
            return ToneEvidence(chroma: [Double](repeating: 0, count: 12),
                                pitch: [Double](repeating: 0, count: Self.pitchFeatureBins))
        }
        for start in starts {
            try Task.checkCancellation()
            let spectrum = performFFTWithWindow(Array(samples[start..<(start + fftSize)]), window: window, size: fftSize)
            let frameMax = Double(spectrum[firstBin...lastBin].max() ?? 0)
            let threshold = frameMax * 0.02
            let prefix = spectralMode == .baseline ? [] : Self.prefixSums(spectrum)
            var peaks: [SpectralPeak] = []
            for bin in firstBin...lastBin {
                let center = Double(spectrum[bin])
                guard center > threshold, center > Double(spectrum[bin - 1]), center >= Double(spectrum[bin + 1]) else { continue }
                // Log-magnitude parabolic interpolation avoids fixed-bin detuning errors.
                let left = log(max(Double(spectrum[bin - 1]), 1e-20))
                let middle = log(max(center, 1e-20))
                let right = log(max(Double(spectrum[bin + 1]), 1e-20))
                let denominator = left - 2 * middle + right
                let offset = denominator < -1e-12 ? max(-0.5, min(0.5, 0.5 * (left - right) / denominator)) : 0
                let frequency = (Double(bin) + offset) * sampleRate / Double(fftSize)
                let pitch = 69 + 12 * log2(frequency / 440)
                guard (33...108).contains(pitch) else { continue }
                let magnitude = exp(middle - 0.25 * (left - right) * offset)
                let chromaWeight = spectralMode == .baseline ? magnitude
                    : magnitude / max(Self.localMean(bin: bin, prefix: prefix), 1e-12 * frameMax)
                peaks.append(SpectralPeak(pitch: pitch, magnitude: magnitude, chromaWeight: chromaWeight))
                let phase = 2 * Double.pi * (pitch - pitch.rounded())
                tuningCos += magnitude * cos(phase)
                tuningSin += magnitude * sin(phase)
                tuningWeight += magnitude
            }
            frames.append(peaks)
        }
        // Circular averaging works across the -50/+50 cent boundary. Diffuse peaks do not imply a tuning shift.
        let concentration = tuningWeight > 0 ? hypot(tuningCos, tuningSin) / tuningWeight : 0
        let tuning = concentration > 0.5 ? atan2(tuningSin, tuningCos) / (2 * .pi) : 0
        var chroma = [Double](repeating: 0, count: 12)
        var pitchEvidence = [Double](repeating: 0, count: Self.pitchFeatureBins)
        for (index, peaks) in frames.enumerated() {
            try Task.checkCancellation()
            var frame = [Double](repeating: 0, count: 12)
            var pitchFrame = [Double](repeating: 0, count: Self.pitchFeatureBins)
            let harmonics = spectralMode == .whitenedHarmonic ? Self.harmonicCount : 1
            for peak in peaks {
                // Attenuate isolated transients; retain notes supported in either adjacent frame.
                let neighbors = [index - 1, index + 1].filter { frames.indices.contains($0) }
                let stable = neighbors.isEmpty || neighbors.contains { neighbor in
                    containsPeak(near: peak.pitch, in: frames[neighbor])
                }
                let weight = peak.chromaWeight * (stable ? 1 : 0.25)
                for harmonic in 1...harmonics {
                    let corrected = peak.pitch - tuning - 12 * log2(Double(harmonic))
                    let note = Int(corrected.rounded())
                    let distance = corrected - Double(note)
                    let pitchWeight = exp(-0.5 * pow(distance / 0.25, 2))
                    let decay = pow(Self.harmonicDecay, Double(harmonic - 1))
                    frame[(note % 12 + 12) % 12] += weight * pitchWeight * decay
                    let pitchBin = note - Self.pitchFeatureLowestNote
                    if harmonic == 1, pitchFrame.indices.contains(pitchBin) {
                        pitchFrame[pitchBin] += weight * pitchWeight
                    }
                }
            }
            let sum = frame.reduce(0, +)
            if sum > 0 {
                for pitch in 0..<12 { chroma[pitch] += frame[pitch] / sum }
            }
            let pitchSum = pitchFrame.reduce(0, +)
            if pitchSum > 0 {
                for bin in pitchFrame.indices { pitchEvidence[bin] += pitchFrame[bin] / pitchSum }
            }
        }
        let sum = chroma.reduce(0, +)
        let pitchTotal = pitchEvidence.reduce(0, +)
        return ToneEvidence(chroma: sum > 0 ? chroma.map { $0 / sum } : chroma,
                            pitch: pitchTotal > 0 ? pitchEvidence.map { $0 / pitchTotal } : pitchEvidence)
    }

    // Peaks follow ascending FFT bins, so temporal matching need not scan every neighbor peak.
    private func containsPeak(near pitch: Double, in peaks: [SpectralPeak]) -> Bool {
        var lower = 0, upper = peaks.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if peaks[middle].pitch < pitch { lower = middle + 1 } else { upper = middle }
        }
        return (lower < peaks.count && abs(peaks[lower].pitch - pitch) < 0.2) ||
               (lower > 0 && abs(peaks[lower - 1].pitch - pitch) < 0.2)
    }

    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        let n = samples.count
        return samples.enumerated().map { index, sample in
            let window = 0.5 - 0.5 * cos(2.0 * .pi * Double(index) / Double(n - 1))
            return sample * Float(window)
        }
    }

    private func performFFT(_ samples: [Float], size: Int) -> [Float] {
        // Use pre-computed FFT setup for better performance
        guard let fftSetup = FFTManager.shared.getFFTSize(for: size),
              let log2n = FFTManager.shared.getLog2n(for: size) else {
            // Fallback for unsupported sizes
            return performFFTFallback(samples, size: size)
        }

        var real = [Float](repeating: 0.0, count: size)
        var imag = [Float](repeating: 0.0, count: size)

        // Copy and zero-pad efficiently
        let copyCount = min(samples.count, size)
        for i in 0..<copyCount {
            real[i] = samples[i]
        }

        // Use split complex for efficient FFT
        var magnitudes = [Float](repeating: 0.0, count: size / 2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute magnitudes using vDSP - much faster than manual calculation
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }

        return magnitudes
    }

    /// Fallback FFT for unsupported sizes
    private func performFFTFallback(_ samples: [Float], size: Int) -> [Float] {
        var real = [Float](repeating: 0.0, count: size)
        var imaginary = [Float](repeating: 0.0, count: size)

        let copyCount = min(samples.count, size)
        for i in 0..<copyCount {
            real[i] = samples[i]
        }

        let log2n = vDSP_Length(log2(Float(size)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else {
            return [Float](repeating: 0.0, count: size)
        }

        var magnitudes = [Float](repeating: 0.0, count: size / 2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imaginary.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }

        vDSP_destroy_fftsetup(fftSetup)
        return magnitudes
    }

    /// Optimized FFT using pre-computed window - combines windowing and FFT
    private func performFFTWithWindow(_ samples: [Float], window: [Float], size: Int) -> [Float] {
        guard let fftSetup = FFTManager.shared.getFFTSize(for: size),
              let log2n = FFTManager.shared.getLog2n(for: size) else {
            let windowed = applyHannWindow(samples)
            return performFFT(windowed, size: size)
        }

        var real = [Float](repeating: 0.0, count: size)
        var imag = [Float](repeating: 0.0, count: size)

        // Apply window using vDSP (SIMD accelerated)
        let sampleCount = min(samples.count, size)
        samples.withUnsafeBufferPointer { samplePtr in
            window.withUnsafeBufferPointer { windowPtr in
                for i in 0..<sampleCount {
                    real[i] = samplePtr[i] * windowPtr[i]
                }
            }
        }

        var magnitudes = [Float](repeating: 0.0, count: size / 2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }

        return magnitudes
    }

    private func correlateWithKeyProfiles(chromagram: [Double], returnTopN: Int = 1) -> [(MusicalKey, Double)] {
        let normalized = normalizeChromagram(chromagram)
        var scores: [(MusicalKey, Double)] = []
        for rotation in 0..<12 {
            let rotated = rotateArray(normalized, by: rotation)
            scores.append((majorKeyForRotation(rotation), calculateCorrelation(chromagram: rotated, profile: style == .edm ? Self.majorProfile : KeyModelWeights.trapMajorProfile)))
            scores.append((minorKeyForRotation(rotation), calculateCorrelation(chromagram: rotated, profile: style == .edm ? Self.minorProfile : KeyModelWeights.trapMinorProfile)))
        }
        scores.sort { $0.1 == $1.1 ? $0.0.rawValue < $1.0.rawValue : $0.1 > $1.1 }
        return Array(scores.prefix(returnTopN))
    }

    private func normalizeChromagram(_ chromagram: [Double]) -> [Double] {
        // Apply spectral whitening to reduce timbral bias
        var normalized = chromagram

        // First pass: standard normalization
        let sum = normalized.reduce(0, +)
        if sum > 0 {
            normalized = normalized.map { $0 / sum }
        }

        // Second pass: adaptive compression based on chromagram sparsity
        // Sparse chromagrams (synth bass) need less compression to preserve distinction
        // Dense chromagrams (full mix) benefit from more compression
        let sparsity = calculateSparsity(normalized)
        let compressionExponent = sparsity > 0.6 ? 0.7 : 0.5
        normalized = normalized.map { pow($0, compressionExponent) }

        // Third pass: re-normalize
        let sum2 = normalized.reduce(0, +)
        if sum2 > 0 {
            normalized = normalized.map { $0 / sum2 }
        }

        return normalized
    }

    // Calculate sparsity of chromagram (1.0 = very sparse, 0.0 = evenly distributed)
    private func calculateSparsity(_ chromagram: [Double]) -> Double {
        let max = chromagram.max() ?? 1.0
        let threshold = max * 0.1
        let activeClasses = chromagram.filter { $0 > threshold }.count
        return 1.0 - (Double(activeClasses) / 12.0)
    }

    private func calculateCorrelation(chromagram: [Double], profile: [Double]) -> Double {
        // Pearson correlation coefficient
        let n = Double(chromagram.count)
        let meanChroma = chromagram.reduce(0, +) / n
        let meanProfile = profile.reduce(0, +) / n

        var covariance = 0.0
        var chromaVariance = 0.0
        var profileVariance = 0.0

        for i in 0..<chromagram.count {
            let chromaDiff = chromagram[i] - meanChroma
            let profileDiff = profile[i] - meanProfile
            covariance += chromaDiff * profileDiff
            chromaVariance += chromaDiff * chromaDiff
            profileVariance += profileDiff * profileDiff
        }

        if chromaVariance == 0 || profileVariance == 0 {
            return 0
        }

        return covariance / sqrt(chromaVariance * profileVariance)
    }

    private func rotateArray<T>(_ array: [T], by offset: Int) -> [T] {
        let count = array.count
        let normalizedOffset = ((offset % count) + count) % count
        return Array(array[normalizedOffset...] + array[..<normalizedOffset])
    }

    private func majorKeyForRotation(_ rotation: Int) -> MusicalKey {
        let keys: [MusicalKey] = [.cMajor, .cSharpMajor, .dMajor, .dSharpMajor, .eMajor, .fMajor,
                                   .fSharpMajor, .gMajor, .gSharpMajor, .aMajor, .aSharpMajor, .bMajor]
        return keys[rotation % 12]
    }

    private func minorKeyForRotation(_ rotation: Int) -> MusicalKey {
        let keys: [MusicalKey] = [.cMinor, .cSharpMinor, .dMinor, .dSharpMinor, .eMinor, .fMinor,
                                   .fSharpMinor, .gMinor, .gSharpMinor, .aMinor, .aSharpMinor, .bMinor]
        return keys[rotation % 12]
    }
}
