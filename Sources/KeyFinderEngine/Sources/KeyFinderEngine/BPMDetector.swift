import Foundation
import Accelerate
import AVFoundation

public class BPMDetector {
    public let method: Method
    public init(method: Method = .combOctave) { self.method = method }

    public enum AnalysisError: Error {
        case invalidSampleRate, invalidSamples
    }

    public func detectBPM(audioSamples: [Float], sampleRate: Double) async throws -> Double {
        try Task.checkCancellation()
        guard sampleRate.isFinite, (4000...192000).contains(sampleRate) else { throw AnalysisError.invalidSampleRate }
        guard audioSamples.allSatisfy({ $0.isFinite }) else { throw AnalysisError.invalidSamples }
        if method != .legacy, let tempo = try await combTempo(samples: audioSamples, sampleRate: sampleRate) {
            return tempo
        }
        return try await legacyTempo(samples: audioSamples, sampleRate: sampleRate)
    }

    func legacyTempo(samples audioSamples: [Float], sampleRate: Double) async throws -> Double {
        // Apply onset detection
        let onsetStrength = await calculateOnsetStrength(samples: audioSamples, sampleRate: sampleRate)
        try Task.checkCancellation()

        // Calculate autocorrelation
        let tempogram = await calculateAutocorrelation(onsetStrength: onsetStrength, sampleRate: sampleRate)
        try Task.checkCancellation()

        // Find peaks corresponding to tempo
        let bpm = findTempoPeak(autocorrelation: tempogram, sampleRate: sampleRate)

        return bpm
    }

    private func calculateOnsetStrength(samples: [Float], sampleRate: Double) async -> [Float] {
        let hopSize = 512
        let fftSize = 2048
        var onsetStrength = [Float]()

        var previousSpectrum = [Float](repeating: 0.0, count: fftSize / 2)

        for frameStart in stride(from: 0, to: samples.count - fftSize, by: hopSize) {
            let frame = Array(samples[frameStart..<min(frameStart + fftSize, samples.count)])

            // Apply Hann window
            let windowedFrame = applyHannWindow(frame)

            // Get magnitude spectrum
            let spectrum = performFFT(windowedFrame, size: fftSize)

            // Calculate spectral flux (onset strength)
            var flux: Float = 0.0
            for i in 0..<spectrum.count {
                let diff = spectrum[i] - previousSpectrum[i]
                flux += max(0, diff) // Half-wave rectification
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

    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        let n = samples.count
        return samples.enumerated().map { index, sample in
            let window = 0.5 - 0.5 * cos(2.0 * .pi * Double(index) / Double(n - 1))
            return sample * Float(window)
        }
    }

    private func performFFT(_ samples: [Float], size: Int) -> [Float] {
        var real = samples
        var imaginary = [Float](repeating: 0.0, count: size)

        // Pad if necessary
        while real.count < size {
            real.append(0.0)
        }

        let log2n = vDSP_Length(log2(Float(size)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else {
            return [Float](repeating: 0.0, count: size / 2)
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

    private func calculateAutocorrelation(onsetStrength: [Float], sampleRate: Double) async -> [Float] {
        let n = onsetStrength.count
        guard n > 1 else { return [] }
        // Tempo search only consumes lags up to one second. Avoid quadratic work on
        // a whole-track envelope now that every second of the timeline is retained.
        let maxLag = min(n - 1, Int(sampleRate / 512) + 1)
        var autocorrelation = [Float](repeating: 0.0, count: maxLag + 1)

        for lag in 0...maxLag {
            var sum: Float = 0.0
            for i in 0..<(n - lag) {
                sum += onsetStrength[i] * onsetStrength[i + lag]
            }
            autocorrelation[lag] = sum
        }

        return autocorrelation
    }

    private func findTempoPeak(autocorrelation: [Float], sampleRate: Double) -> Double {
        let hopSize = 512
        let framesPerSecond = sampleRate / Double(hopSize)

        // BPM range: 60-180 (typical for most music)
        let minBPM = 60.0
        let maxBPM = 180.0

        let minLag = Int(60.0 / maxBPM * framesPerSecond)
        let maxLag = min(Int(60.0 / minBPM * framesPerSecond), autocorrelation.count - 1)
        guard minLag <= maxLag else { return 0 }

        let peaks = (minLag...maxLag).filter { lag in
            lag > 0 && lag + 1 < autocorrelation.count &&
                autocorrelation[lag] > autocorrelation[lag - 1] &&
                autocorrelation[lag] >= autocorrelation[lag + 1]
        }
        guard var chosen = peaks.max(by: { autocorrelation[$0] < autocorrelation[$1] }),
              autocorrelation[chosen] > 0 else { return 0 }
        // Onsets between envelope frames smear the fundamental across two bins,
        // while its double-period peak can land on one. Prefer a supported half-lag.
        if let fundamental = peaks.filter({ abs(Double($0) * 2 - Double(chosen)) <= 2 &&
            autocorrelation[$0] >= autocorrelation[chosen] * 0.55 })
            .max(by: { autocorrelation[$0] < autocorrelation[$1] }) {
            chosen = fundamental
        }
        let left = Double(autocorrelation[chosen - 1])
        let center = Double(autocorrelation[chosen])
        let right = Double(autocorrelation[chosen + 1])
        let denominator = left - 2 * center + right
        let offset = abs(denominator) > 0.000001 ? max(-0.5, min(0.5, 0.5 * (left - right) / denominator)) : 0
        let bpm = 60 * framesPerSecond / (Double(chosen) + offset)
        return round(bpm * 10) / 10
    }
}
