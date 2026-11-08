import Foundation

public struct CueSuggestion: Codable, Equatable {
    public let time: Double
    public let name: String
    public init(time: Double, name: String) { self.time = time; self.name = name }
}

/// Suggestions describe measured changes, not unverified musical section labels.
public enum CuePlanner {
    public static func suggest(samples: [Float], sampleRate: Double, grid: BeatGridDetector.BeatGrid) -> [CueSuggestion] {
        guard sampleRate.isFinite, sampleRate > 0, !samples.isEmpty else { return [] }
        let window = max(1, Int(sampleRate / 2))
        var envelope: [Double] = []
        for start in stride(from: 0, to: samples.count, by: window) {
            let slice = samples[start..<min(start + window, samples.count)]
            envelope.append(sqrt(slice.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(slice.count)))
        }
        return suggest(envelope: envelope, interval: Double(window) / sampleRate,
                       duration: Double(samples.count) / sampleRate,
                       downbeats: grid.beats.filter(\.isDownbeat).map(\.time))
    }

    public static func suggest(envelope: [Double], interval: Double, duration: Double, downbeats: [Double]) -> [CueSuggestion] {
        guard duration.isFinite, duration >= 8, interval.isFinite, interval > 0,
              envelope.count >= 8, envelope.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let peak = envelope.max(), peak > 0.00001 else { return [] }
        let audible = envelope.indices.filter { envelope[$0] > peak * 0.06 }
        guard let first = audible.first, let last = audible.last else { return [] }
        let validBeats = downbeats.filter { $0.isFinite && $0 >= 0 && $0 < duration }.sorted()
        // Without a measured downbeat grid, no cue is advertised as beat-aligned.
        guard !validBeats.isEmpty else { return [] }
        func snap(_ time: Double) -> Double {
            validBeats.min { abs($0 - time) < abs($1 - time) }!
        }
        var candidates: [(Double, String, Double)] = [(Double(first) * interval, "Intro", 10),
            (max(Double(first) * interval, Double(last) * interval - 16), "Outro", 9)]
        let span = max(2, Int(2 / interval))
        if envelope.count > span * 2 {
            for i in span..<(envelope.count - span) {
                let before = envelope[(i - span)..<i].reduce(0, +) / Double(span)
                let after = envelope[i..<(i + span)].reduce(0, +) / Double(span)
                let delta = (after - before) / peak
                if abs(delta) > 0.22 {
                    candidates.append((Double(i) * interval, delta > 0 ? "Energy rise" : "Energy dip", abs(delta)))
                }
            }
        }
        var result: [CueSuggestion] = []
        for candidate in candidates.sorted(by: { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }) {
            let time = snap(candidate.0)
            guard result.allSatisfy({ abs($0.time - time) >= 8 }) else { continue }
            result.append(CueSuggestion(time: time, name: candidate.1))
            if result.count == 8 { break }
        }
        return result.sorted { $0.time < $1.time }
    }
}

public enum EnergyDirection: String, CaseIterable {
    case hold = "Hold", lift = "Lift", ease = "Ease"
}

public struct TransitionAssessment: Equatable {
    public let score: Double
    public let reasons: [String]
}

public enum MixRanker {
    /// Exclude incompatible keys and extreme tempo changes; never randomly fall back
    /// to a clash and show it as a green compatible transition.
    public static func assess(fromKey: String, fromBPM: Double, fromEnergy: String?,
                              toKey: String, toBPM: Double, toEnergy: String?,
                              direction: EnergyDirection = .hold) -> TransitionAssessment? {
        func parse(_ key: String) -> (Int, Character)? {
            guard let mode = key.last, mode == "A" || mode == "B",
                  let number = Int(key.dropLast()), (1...12).contains(number) else { return nil }
            return (number, mode)
        }
        guard let a = parse(fromKey), let b = parse(toKey), fromBPM.isFinite,
              toBPM.isFinite, fromBPM > 0, toBPM > 0 else { return nil }
        let step = min(abs(a.0 - b.0), 12 - abs(a.0 - b.0))
        let harmonic: Double
        let reason: String
        if a == b { harmonic = 1; reason = "Same key" }
        else if a.0 == b.0 { harmonic = 0.94; reason = "Relative major/minor" }
        else if a.1 == b.1 && step == 1 { harmonic = 0.9; reason = "Adjacent Camelot key" }
        else { return nil }
        let tempoDelta = (toBPM - fromBPM) / fromBPM * 100
        guard abs(tempoDelta) <= 8 else { return nil }
        var reasons = [reason, String(format: "Tempo %+.1f%%", tempoDelta)]
        let levels = ["Low": 0, "Medium": 1, "High": 2, "Very High": 3]
        var energyScore = 0.4
        if let from = fromEnergy.flatMap({ levels[$0] }), let to = toEnergy.flatMap({ levels[$0] }) {
            let desired = direction == .lift ? 1 : direction == .ease ? -1 : 0
            energyScore = max(0, 1 - Double(abs(to - from - desired)) / 3)
            reasons.append(to == from ? "Energy holds" : to > from ? "Energy rises" : "Energy eases")
        } else { reasons.append("Energy unavailable") }
        return TransitionAssessment(score: 0.55 * harmonic + 0.3 * (1 - abs(tempoDelta) / 8) + 0.15 * energyScore,
                                    reasons: reasons)
    }
}
