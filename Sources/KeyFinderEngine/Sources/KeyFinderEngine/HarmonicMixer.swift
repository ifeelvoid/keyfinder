import Foundation

/// Harmonic-mixing logic shared by the app and the MCP server: what mixes out of a track,
/// and in what order a folder becomes a set. Deterministic (unlike the app's original
/// random Smart DJ) so an assistant gets the same answer for the same folder.
public enum HarmonicMixer {
    public struct Match: Codable, Equatable, Sendable {
        public let track: TrackSummary
        public let relation: String
        /// Tempo distance in percent, counting half/double time as a match.
        public let bpmDeltaPercent: Double
        public let energyChange: Int
        public let score: Double
    }

    public enum EnergyShape: String, Codable, CaseIterable, Sendable {
        case build, flat, peak
    }

    public struct SetEntry: Codable, Equatable, Sendable {
        public let position: Int
        public let track: TrackSummary
        /// How we got here from the previous track; nil for the opener.
        public let transition: String?
    }

    /// Tracks in `library` that mix harmonically out of `camelot` within `bpmTolerance`
    /// percent, best first. The reference track itself (same path) is excluded.
    public static func compatible(with camelot: CamelotKey, bpm: Double, energyRank: Int? = nil,
                                  excludingPath: String? = nil, in library: [TrackSummary],
                                  bpmTolerance: Double = 6) -> [Match] {
        library.compactMap { track -> Match? in
            guard track.path != excludingPath,
                  let key = track.camelotKey,
                  let relation = camelot.relation(to: key) else { return nil }
            let delta = TempoMatch.distancePercent(from: bpm, to: track.bpm)
            guard delta <= bpmTolerance else { return nil }
            let score = relation.score - delta / 100
            return Match(track: track, relation: relation.rawValue,
                         bpmDeltaPercent: (delta * 10).rounded() / 10,
                         energyChange: track.energyRank - (energyRank ?? track.energyRank),
                         score: (score * 1000).rounded() / 1000)
        }
        .sorted { ($0.score, $1.track.path) > ($1.score, $0.track.path) }
    }

    /// Orders up to `maxTracks` tracks into a set that follows `shape`, preferring harmonic
    /// moves and small tempo changes. Falls back to the closest-tempo clash only when no
    /// compatible track is left, and labels that transition so the DJ knows.
    public static func buildSet(from library: [TrackSummary], start: TrackSummary? = nil,
                                maxTracks: Int = 20, shape: EnergyShape = .build) -> [SetEntry] {
        let pool = library.filter { $0.camelotKey != nil && $0.bpm > 0 }
        let length = min(max(maxTracks, 1), pool.count)
        guard length > 0, let opener = start ?? defaultOpener(pool, shape: shape) else { return [] }

        var remaining = pool.filter { $0.path != opener.path }
        var entries = [SetEntry(position: 1, track: opener, transition: nil)]
        while entries.count < length, !remaining.isEmpty {
            let current = entries[entries.count - 1].track
            let target = targetEnergy(position: entries.count, length: length, shape: shape,
                                      openerRank: opener.energyRank)
            let next = remaining.min { lhs, rhs in
                let l = transitionCost(from: current, to: lhs, targetEnergy: target)
                let r = transitionCost(from: current, to: rhs, targetEnergy: target)
                return (l, lhs.path) < (r, rhs.path)
            }!
            entries.append(SetEntry(position: entries.count + 1, track: next,
                                    transition: describe(from: current, to: next)))
            remaining.removeAll { $0.path == next.path }
        }
        return entries
    }

    // MARK: - Internals

    static func defaultOpener(_ pool: [TrackSummary], shape: EnergyShape) -> TrackSummary? {
        let ordered = pool.sorted { ($0.energyRank, $0.bpm, $0.path) < ($1.energyRank, $1.bpm, $1.path) }
        return shape == .flat ? ordered[ordered.count / 2] : ordered.first
    }

    /// Target energy rank (0...3) for the track at zero-based `position`.
    static func targetEnergy(position: Int, length: Int, shape: EnergyShape, openerRank: Int) -> Double {
        guard length > 1 else { return Double(openerRank) }
        let progress = Double(position) / Double(length - 1)
        switch shape {
        case .flat:
            return Double(openerRank)
        case .build:
            return Double(openerRank) + (3 - Double(openerRank)) * progress
        case .peak:
            // Rise to the top two-thirds of the way in, then come back down.
            let peakAt = 2.0 / 3.0
            let height = progress <= peakAt ? progress / peakAt : (1 - progress) / (1 - peakAt)
            return Double(openerRank) + (3 - Double(openerRank)) * height
        }
    }

    static func transitionCost(from current: TrackSummary, to candidate: TrackSummary,
                               targetEnergy: Double) -> Double {
        let harmonic: Double
        if let from = current.camelotKey, let to = candidate.camelotKey, let relation = from.relation(to: to) {
            harmonic = 1 - relation.score
        } else {
            harmonic = 2  // a clash is allowed only when nothing compatible is left
        }
        let tempo = TempoMatch.distancePercent(from: current.bpm, to: candidate.bpm) / 10
        let energy = abs(Double(candidate.energyRank) - targetEnergy) / 3
        return harmonic + tempo + energy
    }

    static func describe(from current: TrackSummary, to next: TrackSummary) -> String {
        let keyPart: String
        if let from = current.camelotKey, let to = next.camelotKey {
            keyPart = from.relation(to: to).map { "\(from) → \(to), \($0.rawValue)" }
                ?? "\(from) → \(to), key clash (no compatible track left)"
        } else {
            keyPart = "\(current.camelot) → \(next.camelot)"
        }
        let tempo = TempoMatch.distancePercent(from: current.bpm, to: next.bpm)
        return "\(keyPart); \(format(current.bpm)) → \(format(next.bpm)) BPM (\(format(tempo))% tempo move)"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
