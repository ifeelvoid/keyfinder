import Foundation
import Accelerate

// MARK: - Pre-computed Window Functions
/// Pre-computed Hann window for common FFT sizes - avoids recalculating on every frame
public final class WindowCache {
    public static let shared = WindowCache()

    private var hannWindows: [Int: [Float]] = [:]
    private var hammingWindows: [Int: [Float]] = [:]

    private init() {
        // Pre-compute windows for common sizes
        for size in [4096, 8192, 16384, 32768] {
            hannWindows[size] = computeHannWindow(size: size)
            hammingWindows[size] = computeHammingWindow(size: size)
        }
    }

    private func computeHannWindow(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        return window
    }

    private func computeHammingWindow(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        vDSP_hamm_window(&window, vDSP_Length(size), 0)
        return window
    }

    public func getHannWindow(size: Int) -> [Float]? {
        return hannWindows[size]
    }

    public func getHammingWindow(size: Int) -> [Float]? {
        return hammingWindows[size]
    }
}