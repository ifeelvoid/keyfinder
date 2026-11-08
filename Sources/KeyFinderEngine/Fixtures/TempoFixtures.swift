import Foundation
import KeyFinderEngine

/// Briefs #0011/#0012: the bar-level comb must keep the metre on dense-hat trap and
/// four-on-floor patterns that the legacy peak picker reads as ×2 or ½, a fast trap session
/// must land on its tempo or half (never 2/3), and short windows must fall back.
public enum TempoFixtures {
    private struct Failure: Error, CustomStringConvertible { let description: String }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    /// Deterministic drum loop: (beat position, voice) per 4/4 bar. 0 kick, 1 snare, 2 hat.
    static func loop(bpm: Double, pattern: [(Double, Int)], seconds: Double = 40) -> [Float] {
        let rate = 22050.0, beat = 60 / bpm
        var out = [Float](repeating: 0, count: Int(rate * seconds))
        var seed: UInt32 = 11
        func noise() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed) / Double(UInt32.max) * 2 - 1 }
        var bar = 0.0
        while (bar + 1) * 4 * beat < seconds {
            for (position, voice) in pattern {
                let start = Int((bar * 4 + position) * beat * rate)
                for i in 0..<Int(0.12 * rate) where start + i < out.count {
                    let t = Double(i) / rate
                    let value: Double
                    switch voice {
                    case 0: value = sin(2 * .pi * (50 + 80 * exp(-t * 30)) * t) * exp(-t * 12)
                    case 1: value = noise() * exp(-t * 25) * 0.6
                    default: value = noise() * exp(-t * 80) * 0.25
                    }
                    out[start + i] += Float(value * 0.5)
                }
            }
            bar += 1
        }
        return out
    }

    public static func run() async throws -> [String] {
        let trap = [(0.0, 0), (1.5, 0), (2.75, 0), (2.0, 1)] + (0..<16).map { (Double($0) / 4, 2) }
            + (0..<6).map { (3 + Double($0) / 6, 2) }
        let four = (0..<4).map { (Double($0), 0) } + [(1.0, 1), (3.0, 1)] + (0..<4).map { (Double($0) + 0.5, 2) }
        for (bpm, pattern) in [(81.0, trap), (120.0, four)] {
            let audio = loop(bpm: bpm, pattern: pattern)
            let tempo = try await BPMDetector().detectBPM(audioSamples: audio, sampleRate: 22050)
            try require(abs(tempo / bpm - 1) <= 0.02, "Comb must report the session tempo \(bpm), got \(tempo)")
        }
        // Syncopated kicks under 16th hats and sextuplet rolls: #0011's comb read these as 2/3.
        let dense = [(0.0, 0), (0.75, 0), (1.5, 0), (2.0, 1), (3.25, 0)] + (0..<16).map { (Double($0) / 4, 2) }
            + (0..<24).map { (Double($0) / 6, 2) }
        for bpm in [160.0, 174.0] {
            let fast = try await BPMDetector().detectBPM(audioSamples: loop(bpm: bpm, pattern: dense), sampleRate: 22050)
            try require([bpm, bpm / 2].contains { abs(fast / $0 - 1) <= 0.02 }, "Fast \(bpm) BPM trap must read as its tempo or half, got \(fast)")
        }
        let short = Array(loop(bpm: 120, pattern: four).prefix(22050 * 5))
        let fallback = try await BPMDetector().detectBPM(audioSamples: short, sampleRate: 22050)
        let legacy = try await BPMDetector(method: .legacy).detectBPM(audioSamples: short, sampleRate: 22050)
        try require(fallback == legacy && fallback > 0, "Windows shorter than two bars at 60 BPM use the legacy detector")
        return ["Comb keeps metre on 81 BPM and fast 160/174 BPM trap and 120 BPM four-on-floor; 5 s windows fall back to legacy"]
    }
}
