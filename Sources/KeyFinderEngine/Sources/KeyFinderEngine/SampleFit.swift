import Foundation

/// What to do to a sample so it sits in a project's key and tempo.
public struct SampleFit: Codable, Equatable {
    public enum TempoMode: String, Codable {
        case normal
        case halfTime = "half-time"
        case doubleTime = "double-time"
    }

    /// Semitones to transpose, in -5...+6 (the shortest move).
    public let semitoneShift: Int
    /// Key the sample is in after the shift, in the sample's own mode.
    public let keyAfterShift: CamelotKey
    /// Set when the sample already mixes with the project key without transposing
    /// (same key, relative, or one step on the wheel); the shift is then optional.
    public let compatibleWithoutShift: String?
    /// Multiply the sample's tempo by this to hit the target (1.03 = 3% faster).
    public let timeStretchRatio: Double
    public let tempoMode: TempoMode
    public let notes: [String]

    /// - Parameters: sample and target keys/tempos. Mode differences are resolved through
    ///   the relative key: an A-minor loop already fits a C-major project.
    public static func compute(sampleKey: CamelotKey, sampleBPM: Double,
                               targetKey: CamelotKey, targetBPM: Double) -> SampleFit {
        let target = targetKey.mode == sampleKey.mode ? targetKey : targetKey.relative
        let shift = shortestShift(from: sampleKey.tonicPitchClass, to: target.tonicPitchClass)
        let tempo = tempoFit(sampleBPM: sampleBPM, targetBPM: targetBPM)

        let existing = sampleKey.relation(to: targetKey)
        var notes: [String] = []
        if let existing, existing != .sameKey, existing != .relative {
            notes.append("Already compatible without transposing (\(sampleKey) → \(targetKey), \(existing.rawValue)); the shift is only for an exact key match.")
        }
        if target != targetKey {
            notes.append("Matched through the relative key \(target) (same notes as \(targetKey)).")
        }
        if abs(shift) >= 5 {
            notes.append("Large pitch shift (\(shift > 0 ? "+" : "")\(shift)); expect audible artifacts on vocals and melodic loops.")
        }
        if abs(tempo.ratio - 1) > 0.08 {
            notes.append("Stretch over 8%; transients may smear.")
        }
        return SampleFit(semitoneShift: shift, keyAfterShift: target,
                         compatibleWithoutShift: existing?.rawValue,
                         timeStretchRatio: (tempo.ratio * 10_000).rounded() / 10_000,
                         tempoMode: tempo.mode, notes: notes)
    }

    static func shortestShift(from source: Int, to target: Int) -> Int {
        let up = CamelotKey.wrap12(target - source)  // 0...11
        return up > 6 ? up - 12 : up                 // -5...+6
    }

    static func tempoFit(sampleBPM: Double, targetBPM: Double) -> (ratio: Double, mode: TempoMode) {
        guard sampleBPM > 0, targetBPM > 0 else { return (1, .normal) }
        let candidates: [(Double, TempoMode)] = [
            (sampleBPM, .normal), (sampleBPM * 2, .halfTime), (sampleBPM / 2, .doubleTime)
        ]
        // Pick the reading needing the least stretch, measured symmetrically in log space.
        let best = candidates.min { abs(log(targetBPM / $0.0)) < abs(log(targetBPM / $1.0)) }!
        return (targetBPM / best.0, best.1)
    }
}
