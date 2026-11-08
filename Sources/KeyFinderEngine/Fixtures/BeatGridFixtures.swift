import Foundation
import KeyFinderEngine

/// Shared by XCTest and the standalone runner so neither path loses these checks.
public enum BeatGridFixtures {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }
    private static func pulses(downbeatOffset: Int = 0) -> [Float] {
        let rate = 22050.0
        return (0..<Int(rate * 12)).map { sample in
            let beat = sample / Int(rate / 2)
            let phase = sample % Int(rate / 2)
            let amplitude = beat % 4 == downbeatOffset ? 1.0 : 0.2
            return phase < 250 ? Float(amplitude * exp(-Double(phase) / 40)) : 0
        }
    }

    public static func run() async throws -> [String] {
        let rate = 22050.0
        let detector = BeatGridDetector()
        for samples: [Float] in [[], [1], [Float](repeating: 0, count: 2048), [Float](repeating: .nan, count: 4096), [Float](repeating: 0, count: 4096)] {
            var rejected = false
            do { _ = try await detector.detectBeatGrid(audioSamples: samples, sampleRate: rate) }
            catch { rejected = true }
            try require(rejected, "Malformed, silent or insufficient grid samples must throw")
        }
        let audio = pulses(downbeatOffset: 2)
        for badRate in [0.0, -1, Double.nan, .infinity, 1e12] {
            var rejected = false
            do { _ = try await detector.detectBeatGrid(audioSamples: audio, sampleRate: badRate) }
            catch { rejected = true }
            try require(rejected, "Invalid grid sample rate must throw")
            rejected = false
            do { _ = try await BPMDetector().detectBPM(audioSamples: audio, sampleRate: badRate) }
            catch { rejected = true }
            try require(rejected, "Invalid tempo sample rate must throw")
        }
        for bpm in [0.0, -120, Double.nan, .infinity, 1e-300, 1e300] {
            var rejected = false
            do { _ = try await detector.detectBeatGrid(audioSamples: audio, sampleRate: rate, detectedBPM: bpm) }
            catch { rejected = true }
            try require(rejected, "Invalid supplied grid tempo must throw")
        }
        var invalidTempoSamplesRejected = false
        do { _ = try await BPMDetector().detectBPM(audioSamples: [Float](repeating: .infinity, count: 4096), sampleRate: rate) }
        catch { invalidTempoSamplesRejected = true }
        try require(invalidTempoSamplesRejected, "Non-finite tempo samples must throw")
        let emptyTempo = try await BPMDetector().detectBPM(audioSamples: [], sampleRate: rate)
        try require(emptyTempo == 0, "Empty tempo input must retain its zero-evidence result")

        let grid = try await detector.detectBeatGrid(audioSamples: audio, sampleRate: rate, detectedBPM: 120).beatGrid
        try require(grid.beats.count > 8, "Pulse fixture must retain beats")
        try require(grid.firstDownbeatTime == grid.beats.first(where: \.isDownbeat)?.time, "First downbeat must agree with beat flags")
        for beat in grid.beats {
            let offset = Int(round((beat.time - grid.firstDownbeatTime) / 0.5))
            let expected = ((offset % grid.beatsPerBar) + grid.beatsPerBar) % grid.beatsPerBar + 1
            try require(beat.beatNumber == expected && beat.isDownbeat == (beat.beatNumber == 1), "Beat numbering must follow measured downbeat")
        }
        try require(!grid.beats[0].isDownbeat, "Pickup beat must not override the stronger measured downbeat")
        let before = grid.firstDownbeatTime - 0.125
        try require(abs(grid.phase(at: before) - 0.75) < 1e-8, "Phase before the first downbeat must wrap into [0,1)")
        try require(abs(grid.timeToNextDownbeat(from: before) - 0.125) < 1e-8, "Next downbeat before the grid starts is the measured first downbeat")
        try require(abs(grid.timeToNextDownbeat(from: grid.firstDownbeatTime) - 2) < 1e-8, "At a downbeat the next downbeat is one bar later")
        try require(grid.phase(at: .nan) == 0 && grid.timeToNextDownbeat(from: .infinity) == 0, "Malformed playback positions must not trap")

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await detector.detectBeatGrid(audioSamples: audio, sampleRate: rate)
        }
        var cancellationReceived = false
        do { _ = try await cancelled.value } catch is CancellationError { cancellationReceived = true }
        try require(cancellationReceived, "Cancelled grid detection must propagate cancellation")
        return ["Beat-grid and tempo malformed inputs reject without trapping",
                "Pickup beats and numbering follow the measured downbeat",
                "Pre-downbeat phase and next-downbeat timing remain bounded",
                "Beat-grid cancellation propagates"]
    }
}
