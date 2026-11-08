import Foundation

/// Coordinates audio callbacks with async analysis without an unbounded task backlog.
/// Keeps a rolling window (up to `maximumSeconds`) and offers it for analysis after every
/// `stepSeconds` of new audio, so the live key settles as more of the track is heard.
final class LiveAnalysisWindow {
    static let stepSeconds = 5.0
    static let maximumSeconds = 30.0

    struct Work {
        let generation: UInt64
        let samples: [Float]
        let sampleRate: Double
    }
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var active = false
    private var inFlight = false
    private var sampleRate: Double = 0
    private var samples: [Float] = []
    private var newSamples = 0

    @discardableResult
    func begin(sampleRate: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        samples.removeAll()
        newSamples = 0
        inFlight = false
        self.sampleRate = sampleRate
        active = sampleRate.isFinite && (4000...192000).contains(sampleRate)
        return active
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        active = false
        inFlight = false
        samples.removeAll()
        newSamples = 0
    }

    func append(_ incoming: [Float], sampleRate: Double) -> Work? {
        lock.lock()
        defer { lock.unlock() }
        guard active, sampleRate == self.sampleRate else { return nil }
        let step = Int(sampleRate * Self.stepSeconds)
        let maximum = Int(sampleRate * Self.maximumSeconds)
        samples.append(contentsOf: incoming)
        newSamples += incoming.count
        // Trim in one-second chunks rather than shifting the buffer on every callback.
        if samples.count > maximum + Int(sampleRate) { samples.removeFirst(samples.count - maximum) }
        guard !inFlight, newSamples >= step else { return nil }
        inFlight = true
        newSamples = 0
        return Work(generation: generation, samples: Array(samples.suffix(maximum)), sampleRate: sampleRate)
    }

    func isCurrent(_ work: Work) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active && generation == work.generation
    }

    /// Returns false when an earlier capture session finishes after stop/restart.
    @discardableResult
    func finish(_ work: Work) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active, generation == work.generation else { return false }
        inFlight = false
        return true
    }
}
