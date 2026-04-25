import Foundation
import Accelerate
import AVFoundation
import os.log

public class KeyDetector {
    // Krumhansl-Schmuckler key profiles (cognitive weights)
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    public init() {}

    public enum MusicalKey: String {
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

    // NEW: Detect key with key change information
    public func detectKeyWithChanges(audioSamples: [Float], sampleRate: Double) async throws -> (MusicalKey, Double, [(TimeInterval, MusicalKey, Double)]) {
        // Use 5 segments for more robust analysis (increased from 3)
        let segmentLength = min(audioSamples.count, Int(sampleRate * 30)) // Max 30 seconds per segment
        let numSegments = 5
        var segmentResults: [(MusicalKey, Double, Double, Double, TimeInterval)] = [] // (key, correlation, energy, harmonicFlux, timestamp)

        for i in 0..<numSegments {
            let segmentStart = (audioSamples.count / (numSegments + 1)) * (i + 1)
            let segmentEnd = min(segmentStart + segmentLength, audioSamples.count)

            if segmentEnd > segmentStart {
                let segment = Array(audioSamples[segmentStart..<segmentEnd])
                let timestamp = Double(segmentStart) / sampleRate

                // Calculate segment energy for weighting
                let segmentEnergy = segment.map { Double($0 * $0) }.reduce(0, +)

                // Calculate chromagram for this segment
                let chromagram = await calculateChromagram(samples: segment, sampleRate: sampleRate)

                // NEW: Calculate harmonic change flux for this segment
                let harmonicFlux = await calculateHarmonicFlux(samples: segment, sampleRate: sampleRate)

                // Get top 3 key candidates with confidence scores
                let candidates = correlateWithKeyProfiles(chromagram: chromagram, returnTopN: 3)

                // Store top candidate with energy, flux, and timestamp
                if let top = candidates.first {
                    segmentResults.append((top.0, top.1, segmentEnergy, harmonicFlux, timestamp))
                }
            }
        }

        // Detect and remove outliers
        let filteredResults = removeOutliers(segmentResults)

        // Weight votes by confidence, energy, AND harmonic flux
        var keyVotes: [MusicalKey: Double] = [:]
        for (key, correlation, energy, flux, _) in filteredResults {
            // Sections with more harmonic change are better indicators of key
            let fluxBonus = 1.0 + (flux * 0.5) // Up to 50% bonus for high-flux sections
            let weight = correlation * sqrt(energy) * fluxBonus
            keyVotes[key, default: 0.0] += weight
        }

        // Return key with most votes and calculate enhanced confidence
        let sorted = keyVotes.sorted { $0.value > $1.value }
        let detectedKey = sorted.first?.key ?? .cMajor
        let topScore = sorted.first?.value ?? 0
        let secondScore = sorted.count > 1 ? sorted[1].value : 0

        // Base confidence from score difference
        var confidence = min(1.0, max(0.0, (topScore - secondScore) / max(topScore, 0.001)))

        // Consistency bonus: How many segments agreed?
        let agreementCount = filteredResults.filter { $0.0 == detectedKey }.count
        let consistencyBonus = Double(agreementCount) / Double(max(filteredResults.count, 1))

        // NEW: Chord progression analysis bonus
        var finalKey = detectedKey
        let progressionScore = await analyzeChordProgressions(samples: audioSamples, sampleRate: sampleRate, candidateKey: detectedKey)

        // If top 2 keys are close, use chord progression to decide
        if sorted.count >= 2 && (topScore - secondScore) / topScore < 0.15 {
            let secondKey = sorted[1].key
            let secondProgressionScore = await analyzeChordProgressions(samples: audioSamples, sampleRate: sampleRate, candidateKey: secondKey)

            // If second key has significantly better chord progression match, switch to it
            if secondProgressionScore > progressionScore * 1.3 {
                print("DEBUG: Chord progression analysis prefers \(secondKey.rawValue) over \(detectedKey.rawValue)")
                finalKey = secondKey
                confidence = min(1.0, confidence * 1.15) // Boost confidence since we have progression confirmation
            }
        }

        // Blend base confidence with consistency and progression
        confidence = confidence * 0.6 + consistencyBonus * 0.25 + (progressionScore * 0.15)

        // NEW: Detect key changes - look for segments with different keys
        var keyChanges: [(TimeInterval, MusicalKey, Double)] = []
        var currentKey: MusicalKey?

        for (key, correlation, _, _, timestamp) in filteredResults {
            if currentKey == nil || key != currentKey {
                keyChanges.append((timestamp, key, correlation))
                currentKey = key
            }
        }

        return (finalKey, confidence, keyChanges)
    }

    // Remove outlier segments based on majority voting
    private func removeOutliers(_ results: [(MusicalKey, Double, Double, Double, TimeInterval)]) -> [(MusicalKey, Double, Double, Double, TimeInterval)] {
        guard results.count >= 3 else { return results }

        // Count frequency of each key
        var keyCounts: [MusicalKey: Int] = [:]
        for (key, _, _, _, _) in results {
            keyCounts[key, default: 0] += 1
        }

        // If any key appears in majority, keep only those and related keys
        let maxCount = keyCounts.values.max() ?? 0
        if maxCount >= results.count / 2 {
            let majorityKey = keyCounts.first(where: { $0.value == maxCount })?.key

            return results.filter { (key, _, _, _, _) in
                key == majorityKey || isRelatedKey(key, to: majorityKey)
            }
        }

        return results // No clear majority, keep all
    }

    // Check if keys are harmonically related (same tonic or P4/P5 apart)
    private func isRelatedKey(_ key1: MusicalKey?, to key2: MusicalKey?) -> Bool {
        guard let k1 = key1, let k2 = key2 else { return false }

        let t1 = tonicPitchClass(k1)
        let t2 = tonicPitchClass(k2)
        let interval = abs((t2 - t1 + 12) % 12)

        // Related keys: same tonic, P5 (7 semitones), or P4 (5 semitones) apart
        return interval == 0 || interval == 5 || interval == 7
    }

    private func calculateChromagram(samples: [Float], sampleRate: Double) async -> [Double] {
        // Pre-fetch window for the FFT size we're using
        let fftSize = 32768
        let hopSize = fftSize / 8
        var pitchClassProfile = [Double](repeating: 0.0, count: 12)
        var melodicProfile = [Double](repeating: 0.0, count: 12)
        var frameCount = 0

        // Pre-get window - avoid computing on every frame
        let hannWindow = WindowCache.shared.getHannWindow(size: fftSize) ?? {
            // Compute Hann window if not cached (shouldn't happen for common sizes)
            var window = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            return window
        }()

        // Process audio in frames - use chunked processing for better memory locality
        let totalSamples = samples.count - fftSize
        guard totalSamples > 0 else { return pitchClassProfile }

        // Pre-calculate note frequencies once
        let noteFrequencies = getNoteFrequencies()

        // Calculate bins per frequency range for octave weighting
        // This avoids computing bin index multiple times per frame
        let binRanges: [(minFreq: Double, maxFreq: Double, weight: Double)] = [
            (0, 130, 2.0),
            (130, 260, 4.0),
            (260, 520, 6.0),
            (520, 1040, 5.0),
            (1040, 2080, 3.0),
            (2080, Double(sampleRate / 2), 1.0)
        ]

        // Pre-compute frequency to bin mappings for efficiency
        var freqToBin: [(freq: Double, bin: Int, pitchClass: Int, octaveWeight: Double)] = []
        for (pitchClass, frequencies) in noteFrequencies.enumerated() {
            for freq in frequencies {
                if freq < sampleRate / 2 {
                    let bin = Int(freq * Double(fftSize) / sampleRate)
                    // Find matching frequency range
                    var weight = 1.0
                    for range in binRanges {
                        if freq >= range.minFreq && freq < range.maxFreq {
                            weight = range.weight
                            break
                        }
                    }
                    freqToBin.append((freq, bin, pitchClass, weight))
                }
            }
        }

        // Process frames with autoreleasepool for memory efficiency
        for frameStart in stride(from: 0, to: totalSamples, by: hopSize) {
            autoreleasepool {
                let frame = Array(samples[frameStart..<min(frameStart + fftSize, samples.count)])
                let spectrum = performFFTWithWindow(frame, window: hannWindow, size: fftSize)

                var frameChroma = [Double](repeating: 0.0, count: 12)
                var frameMelody = [Double](repeating: 0.0, count: 12)

                // Use pre-computed frequency mappings - much faster than nested loops
                for entry in freqToBin {
                    if entry.bin > 0 && entry.bin < spectrum.count {
                        let magnitude = Double(spectrum[entry.bin])
                        let peakMag: Double

                        // Simple peak detection
                        if entry.bin > 1 && entry.bin < spectrum.count - 2 {
                            peakMag = max(magnitude,
                                        max(Double(spectrum[entry.bin-1]),
                                            Double(spectrum[entry.bin+1])))
                        } else {
                            peakMag = magnitude
                        }

                        frameChroma[entry.pitchClass] += peakMag * entry.octaveWeight

                        // Track melodic content
                        if entry.freq >= 260 && entry.freq < 2080 {
                            let melodicWeight = entry.freq < 1040 ? 3.0 : 2.0
                            frameMelody[entry.pitchClass] += peakMag * melodicWeight
                        }
                    }
                }

                // Accumulate profiles
                let harmonicSuppressed = suppressHarmonics(frameChroma)
                for i in 0..<12 {
                    pitchClassProfile[i] += harmonicSuppressed[i]
                    melodicProfile[i] += frameMelody[i]
                }
                frameCount += 1
            }
        }

        // Average across frames
        if frameCount > 0 {
            let divisor = Double(frameCount)
            pitchClassProfile = pitchClassProfile.map { $0 / divisor }
            melodicProfile = melodicProfile.map { $0 / divisor }
        }

        // Blend harmonic and melodic profiles
        var blendedProfile = [Double](repeating: 0.0, count: 12)
        for i in 0..<12 {
            blendedProfile[i] = melodicProfile[i] * 0.6 + pitchClassProfile[i] * 0.4
        }

        return blendedProfile
    }

    // Generate frequencies for each pitch class across multiple octaves
    private func getNoteFrequencies() -> [[Double]] {
        let a4 = 440.0
        var noteFreqs: [[Double]] = Array(repeating: [], count: 12)

        // C, C#, D, D#, E, F, F#, G, G#, A, A#, B
        let semitonesFromA = [-9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2]

        for octave in 1...6 { // Octaves 1-6 cover bass to treble
            for (pitchClass, semitone) in semitonesFromA.enumerated() {
                let octaveShift = (octave - 4) * 12
                let totalSemitones = Double(semitone + octaveShift)
                let frequency = a4 * pow(2.0, totalSemitones / 12.0)
                noteFreqs[pitchClass].append(frequency)
            }
        }

        return noteFreqs
    }

    // Enhance fundamentals - DISABLE harmonic suppression that was causing issues
    private func suppressHarmonics(_ chroma: [Double]) -> [Double] {
        // SIMPLIFIED: Just return the raw chroma without manipulation
        // The old logic was actively making things worse for modern production
        return chroma
    }

    // Detect if bass is artificially enhanced (synth) vs natural
    private func calculateSpectralBalance(_ spectrum: [Float], sampleRate: Double, fftSize: Int) -> Double {
        var subBassEnergy = 0.0
        var midEnergy = 0.0

        for (bin, mag) in spectrum.enumerated() {
            let freq = Double(bin) * sampleRate / Double(fftSize)

            if freq < 130 {
                subBassEnergy += Double(mag * mag)
            } else if freq >= 200 && freq < 1000 {
                midEnergy += Double(mag * mag)
            }
        }

        // High ratio = synth-like (strong bass, weak mids)
        // Low ratio = natural (balanced)
        return subBassEnergy / max(midEnergy, 0.001)
    }

    // Calculate harmonic change flux - sections with more harmonic changes indicate key better
    private func calculateHarmonicFlux(samples: [Float], sampleRate: Double) async -> Double {
        let fftSize = 8192 // Smaller FFT for faster temporal resolution
        let hopSize = fftSize / 2
        var previousChroma = [Double](repeating: 0.0, count: 12)
        var fluxSum = 0.0
        var frameCount = 0

        for frameStart in stride(from: 0, to: samples.count - fftSize, by: hopSize) {
            let frame = Array(samples[frameStart..<min(frameStart + fftSize, samples.count)])
            let windowedFrame = applyHannWindow(frame)
            let spectrum = performFFT(windowedFrame, size: fftSize)

            // Calculate simple chromagram
            var chroma = [Double](repeating: 0.0, count: 12)
            let noteFreqs = getNoteFrequencies()

            for (pitchClass, frequencies) in noteFreqs.enumerated() {
                for freq in frequencies where freq < sampleRate / 2 {
                    let bin = Int(freq * Double(fftSize) / sampleRate)
                    if bin > 0 && bin < spectrum.count {
                        chroma[pitchClass] += Double(spectrum[bin])
                    }
                }
            }

            // Calculate flux (difference from previous frame)
            if frameCount > 0 {
                var flux = 0.0
                for i in 0..<12 {
                    flux += abs(chroma[i] - previousChroma[i])
                }
                fluxSum += flux
            }

            previousChroma = chroma
            frameCount += 1
        }

        // Normalize flux by frame count
        return frameCount > 1 ? fluxSum / Double(frameCount - 1) : 0.0
    }

    // NEW: Analyze temporal chord progression patterns
    private func analyzeChordProgressions(samples: [Float], sampleRate: Double, candidateKey: MusicalKey) async -> Double {
        let fftSize = 16384
        let hopSize = fftSize / 4
        var chromaSequence: [[Double]] = []

        // Extract chromagram sequence
        for frameStart in stride(from: 0, to: min(samples.count - fftSize, Int(sampleRate * 60)), by: hopSize) {
            let frame = Array(samples[frameStart..<min(frameStart + fftSize, samples.count)])
            let windowedFrame = applyHannWindow(frame)
            let spectrum = performFFT(windowedFrame, size: fftSize)

            var chroma = [Double](repeating: 0.0, count: 12)
            let noteFreqs = getNoteFrequencies()

            for (pitchClass, frequencies) in noteFreqs.enumerated() {
                for freq in frequencies where freq < sampleRate / 2 {
                    let bin = Int(freq * Double(fftSize) / sampleRate)
                    if bin > 0 && bin < spectrum.count {
                        chroma[pitchClass] += Double(spectrum[bin])
                    }
                }
            }

            // Normalize
            let sum = chroma.reduce(0, +)
            if sum > 0 {
                chroma = chroma.map { $0 / sum }
            }

            chromaSequence.append(chroma)
        }

        guard chromaSequence.count >= 4 else { return 0.0 }

        // Common chord progressions in each key (relative to tonic)
        let commonProgressions: [[Int]] = [
            [0, 7, 4, 5],    // I-V-III-IV (very common in pop)
            [0, 5, 7, 5],    // I-IV-V-IV (classic progression)
            [0, 4, 7, 0],    // I-III-V-I (strong resolution)
            [0, 9, 7, 5],    // I-VI-V-IV (pop progression)
            [0, 7, 9, 5],    // I-V-VI-IV (Axis progression - extremely common)
            [0, 5, 0, 7],    // I-IV-I-V (simple alternation)
            [9, 5, 0, 7],    // VI-IV-I-V (minor variation)
        ]

        let tonic = tonicPitchClass(candidateKey)
        var maxScore = 0.0

        // Test each progression
        for progression in commonProgressions {
            var score = 0.0
            let windowSize = 4

            for i in 0..<(chromaSequence.count - windowSize) {
                let window = Array(chromaSequence[i..<(i + windowSize)])

                // Check if this window matches the progression
                var matchScore = 0.0
                for (j, rootOffset) in progression.enumerated() {
                    let expectedRoot = (tonic + rootOffset) % 12
                    matchScore += window[j][expectedRoot]
                }

                score = max(score, matchScore / Double(windowSize))
            }

            maxScore = max(maxScore, score)
        }

        return maxScore
    }

    // Resolve ambiguity between keys a perfect 5th apart (C/G, D/A, etc.)
    private func disambiguatePerfectFifth(
        chromagram: [Double],
        key1: MusicalKey,
        key2: MusicalKey
    ) -> MusicalKey {
        // Extract tonic pitch classes
        let tonic1 = tonicPitchClass(key1)
        let tonic2 = tonicPitchClass(key2)

        // Check if they're P5 apart
        guard (tonic2 - tonic1 + 12) % 12 == 7 || (tonic1 - tonic2 + 12) % 12 == 7 else {
            return key1 // Not P5 relationship, return higher scored
        }

        // For P5 relationship: check subdominant (IV) vs dominant (V) strength
        // The real tonic usually has a stronger subdominant than dominant
        // because IV is more stable than V in tonal music
        let key1_subdominant = chromagram[(tonic1 + 5) % 12] // IV of key1
        let key2_subdominant = chromagram[(tonic2 + 5) % 12] // IV of key2

        if key1_subdominant > key2_subdominant * 1.2 {
            return key1
        } else {
            return key2
        }
    }

    // Check if two keys are a perfect 5th apart
    private func isPerfectFifthRelationship(_ key1: MusicalKey, _ key2: MusicalKey) -> Bool {
        let tonic1 = tonicPitchClass(key1)
        let tonic2 = tonicPitchClass(key2)
        let interval = abs((tonic2 - tonic1 + 12) % 12)
        return interval == 7 || interval == 5 // P5 up or down
    }

    // Map each key to its tonic pitch class (0=C, 1=C#, etc.)
    private func tonicPitchClass(_ key: MusicalKey) -> Int {
        let tonics: [MusicalKey: Int] = [
            .cMajor: 0, .cMinor: 0,
            .cSharpMajor: 1, .cSharpMinor: 1,
            .dMajor: 2, .dMinor: 2,
            .dSharpMajor: 3, .dSharpMinor: 3,
            .eMajor: 4, .eMinor: 4,
            .fMajor: 5, .fMinor: 5,
            .fSharpMajor: 6, .fSharpMinor: 6,
            .gMajor: 7, .gMinor: 7,
            .gSharpMajor: 8, .gSharpMinor: 8,
            .aMajor: 9, .aMinor: 9,
            .aSharpMajor: 10, .aSharpMinor: 10,
            .bMajor: 11, .bMinor: 11
        ]
        return tonics[key] ?? 0
    }

    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        let n = samples.count
        return samples.enumerated().map { index, sample in
            let window = 0.5 - 0.5 * cos(2.0 * .pi * Double(index) / Double(n - 1))
            return sample * Float(window)
        }
    }

    private func applyHammingWindow(_ samples: [Float]) -> [Float] {
        let n = samples.count
        return samples.enumerated().map { index, sample in
            let window = 0.54 - 0.46 * cos(2.0 * .pi * Double(index) / Double(n - 1))
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

    private func frequencyToPitchClass(_ frequency: Double) -> Int {
        let a4 = 440.0
        let halfStepsFromA4 = 12 * log2(frequency / a4)
        let pitchClass = (Int(round(halfStepsFromA4)) + 9 + 1200) % 12 // +9 to start from C
        return pitchClass
    }

    private func correlateWithKeyProfiles(chromagram: [Double], returnTopN: Int = 1) -> [(MusicalKey, Double)] {
        var correlations: [(MusicalKey, Double)] = []

        // Normalize chromagram first
        let normalizedChromagram = normalizeChromagram(chromagram)

        // Test all 24 keys (12 major + 12 minor)
        for rotation in 0..<12 {
            // Major key
            let majorCorrelation = calculateCorrelation(
                chromagram: rotateArray(normalizedChromagram, by: rotation),
                profile: KeyDetector.majorProfile
            )
            correlations.append((majorKeyForRotation(rotation), majorCorrelation))

            // Minor key
            let minorCorrelation = calculateCorrelation(
                chromagram: rotateArray(normalizedChromagram, by: rotation),
                profile: KeyDetector.minorProfile
            )
            correlations.append((minorKeyForRotation(rotation), minorCorrelation))
        }

        // Sort by correlation (highest first)
        correlations.sort { $0.1 > $1.1 }

        // Check if top 2 are perfect 5th apart with close scores
        if correlations.count >= 2 {
            let top1 = correlations[0]
            let top2 = correlations[1]

            print("DEBUG: Top 2 keys: \(top1.0.rawValue) (\(top1.1)), \(top2.0.rawValue) (\(top2.1))")
            print("DEBUG: Score difference: \(top1.1 - top2.1)")
            print("DEBUG: Is P5 relationship: \(isPerfectFifthRelationship(top1.0, top2.0))")

            // If very close scores AND perfect 5th relationship, use disambiguation
            if (top1.1 - top2.1) < 0.05 && isPerfectFifthRelationship(top1.0, top2.0) {
                print("DEBUG: Using P5 disambiguation")
                let resolved = disambiguatePerfectFifth(
                    chromagram: normalizedChromagram,
                    key1: top1.0,
                    key2: top2.0
                )
                print("DEBUG: Resolved to: \(resolved.rawValue)")

                // Reorder if needed
                if resolved == top2.0 {
                    correlations.swapAt(0, 1)
                    print("DEBUG: Swapped top 2")
                }
            }
        }

        // Convert correlations to confidence scores (0-1 range)
        let maxCorr = correlations.first?.1 ?? 1.0
        let minCorr = correlations.last?.1 ?? 0.0
        let range = max(maxCorr - minCorr, 0.001) // Avoid division by zero

        // Enhanced confidence scaling - non-linear for better differentiation
        let confidenceScores = correlations.prefix(returnTopN).map { (key, corr) -> (MusicalKey, Double) in
            let normalizedScore = (corr - minCorr) / range
            let confidence = pow(normalizedScore, 0.8) // Less aggressive than linear
            return (key, confidence)
        }

        return Array(confidenceScores)
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