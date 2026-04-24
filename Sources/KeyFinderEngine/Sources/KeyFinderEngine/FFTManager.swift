import Foundation
import Accelerate
import os.log

// MARK: - Performance Optimized FFT Manager
/// Singleton FFT setup for reuse - avoid recreating FFT plans on every call
/// This provides significant performance improvement for repeated FFT operations
public final class FFTManager {
    public static let shared = FFTManager()

    private var fftSetup4096: FFTSetup?
    private var fftSetup8192: FFTSetup?
    private var fftSetup16384: FFTSetup?
    private var fftSetup32768: FFTSetup?

    private let log2n_4096 = vDSP_Length(log2(Double(4096)))
    private let log2n_8192 = vDSP_Length(log2(Double(8192)))
    private let log2n_16384 = vDSP_Length(log2(Double(16384)))
    private let log2n_32768 = vDSP_Length(log2(Double(32768)))

    private init() {
        // Pre-create FFT setups for common sizes - these are thread-safe to reuse
        fftSetup4096 = vDSP_create_fftsetup(log2n_4096, Int32(kFFTRadix2))
        fftSetup8192 = vDSP_create_fftsetup(log2n_8192, Int32(kFFTRadix2))
        fftSetup16384 = vDSP_create_fftsetup(log2n_16384, Int32(kFFTRadix2))
        fftSetup32768 = vDSP_create_fftsetup(log2n_32768, Int32(kFFTRadix2))
    }

    deinit {
        if let setup = fftSetup4096 { vDSP_destroy_fftsetup(setup) }
        if let setup = fftSetup8192 { vDSP_destroy_fftsetup(setup) }
        if let setup = fftSetup16384 { vDSP_destroy_fftsetup(setup) }
        if let setup = fftSetup32768 { vDSP_destroy_fftsetup(setup) }
    }

    public func getFFTSize(for size: Int) -> FFTSetup? {
        switch size {
        case 4096: return fftSetup4096
        case 8192: return fftSetup8192
        case 16384: return fftSetup16384
        case 32768: return fftSetup32768
        default: return nil
        }
    }

    public func getLog2n(for size: Int) -> vDSP_Length? {
        switch size {
        case 4096: return log2n_4096
        case 8192: return log2n_8192
        case 16384: return log2n_16384
        case 32768: return log2n_32768
        default: return nil
        }
    }
}