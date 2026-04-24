import Foundation
import Accelerate
import AVFoundation

public class BPMDetector {
    public func detectBPM(audioSamples: [Float], sampleRate: Double) async throws -> Double {
        // Apply onset detection
        let onsetStrength = await calculateOnsetStrength(samples: audioSamples, sampleRate: sampleRate)

        // Calculate autocorrelation
        let tempogram = await calculateAutocorrelation(onsetStrength: onsetStrength)

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

    private func calculateAutocorrelation(onsetStrength: [Float]) async -> [Float] {
        let n = onsetStrength.count
        var autocorrelation = [Float](repeating: 0.0, count: n)

        for lag in 0..<n {
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

        var maxPeak: Float = 0.0
        var maxPeakLag = minLag

        // Find the peak in the autocorrelation within the BPM range
        for lag in minLag...maxLag {
            if autocorrelation[lag] > maxPeak {
                // Check if it's a local maximum
                if lag > 0 && lag < autocorrelation.count - 1 {
                    if autocorrelation[lag] > autocorrelation[lag - 1] &&
                       autocorrelation[lag] > autocorrelation[lag + 1] {
                        maxPeak = autocorrelation[lag]
                        maxPeakLag = lag
                    }
                }
            }
        }

        // Convert lag to BPM
        let bpm = 60.0 * framesPerSecond / Double(maxPeakLag)

        // Round to one decimal place
        return round(bpm * 10) / 10
    }
}