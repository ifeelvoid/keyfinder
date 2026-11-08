import Foundation

/// Which template set the detector correlates against.
public enum KeyStyle: String, CaseIterable, Codable, Sendable {
    case trapHipHop
    case edm

    public var displayName: String { self == .edm ? "EDM" : "Trap / Hip-Hop" }

    /// UserDefaults / @AppStorage key shared by the app's settings and analysis paths.
    public static let storageKey = "keyStyle"
    /// Alexander's default; unknown or missing stored values fall back to it.
    public static let defaultStyle = KeyStyle.trapHipHop

    public static func stored(in defaults: UserDefaults = .standard) -> KeyStyle {
        defaults.string(forKey: storageKey).flatMap(KeyStyle.init(rawValue:)) ?? defaultStyle
    }
}

/// Template correlation (#0004/#0010 profiles) or the #0010 key-equivariant model.
public enum KeyMethod: String, CaseIterable, Codable, Sendable {
    case templates
    case model
}

extension KeyDetector {
    /// The detector configuration adopted for each style by brief #0010's frozen acceptance run
    /// (docs/briefs/0010-genre-key-models/ledger.md): the key model won for both styles; the
    /// catalog-fitted Trap / Hip-Hop templates were rejected, so template fallback stays learned50.
    public static func configured(for style: KeyStyle) -> KeyDetector {
        KeyDetector(style: adoptedTemplates(for: style), method: adoptedMethod(for: style))
    }

    public static func adoptedMethod(for style: KeyStyle) -> KeyMethod {
        switch style {
        case .trapHipHop: return .model
        case .edm: return .model
        }
    }

    /// Template set used when the model has no usable pitch evidence.
    public static func adoptedTemplates(for style: KeyStyle) -> KeyStyle {
        switch style {
        case .trapHipHop: return .edm // candidate T rejected on the held-out catalog half
        case .edm: return .edm
        }
    }

    /// Model input: log1p(1000 · mean semitone evidence). Nil when no segment carries pitch evidence.
    static func modelInput(_ pitches: [[Double]]) -> [Double]? {
        let usable = pitches.filter { $0.count == pitchFeatureBins && $0.reduce(0, +) > 0 }
        guard !usable.isEmpty else { return nil }
        return (0..<pitchFeatureBins).map { bin in
            log1p(1000 * usable.reduce(0.0) { $0 + $1[bin] } / Double(usable.count))
        }
    }

    /// 24 logits ordered like MusicalKey.allCases (majors C...B, then minors C...B).
    static func modelLogits(_ input: [Double]) -> [Double] {
        var logits = [Double](repeating: 0, count: 24)
        let hidden = KeyModelWeights.hiddenUnits
        for tonic in 0..<12 {
            var output = KeyModelWeights.outputBias
            for unit in 0..<hidden {
                var sum = KeyModelWeights.hiddenBias[unit]
                let row = unit * pitchFeatureBins
                for bin in 0..<(pitchFeatureBins - tonic) {
                    sum += KeyModelWeights.hiddenWeights[row + bin] * input[bin + tonic]
                }
                guard sum > 0 else { continue }
                output[0] += KeyModelWeights.outputWeights[unit] * sum
                output[1] += KeyModelWeights.outputWeights[hidden + unit] * sum
            }
            logits[tonic] = output[0]
            logits[12 + tonic] = output[1]
        }
        return logits
    }

    static func modelProbabilities(_ input: [Double]) -> [Double] {
        let logits = modelLogits(input)
        let top = logits.max() ?? 0
        let exps = logits.map { exp($0 - top) }
        let total = exps.reduce(0, +)
        return exps.map { $0 / total }
    }

    /// First index wins ties, matching numpy argmax in the training/reference tools.
    private static func ranked(_ probabilities: [Double]) -> (MusicalKey, Double) {
        var best = 0, second = -1
        for index in probabilities.indices.dropFirst() {
            if probabilities[index] > probabilities[best] { second = best; best = index }
            else if second < 0 || probabilities[index] > probabilities[second] { second = index }
        }
        if second < 0 { second = best == 0 ? 1 : 0 }
        return (MusicalKey.allCases[best], max(0, min(1, probabilities[best] - probabilities[second])))
    }

    func modelDetection(segments: [TonalSegment]) -> (MusicalKey, Double, [(TimeInterval, MusicalKey, Double)])? {
        guard let input = Self.modelInput(segments.compactMap(\.pitch)) else { return nil }
        let (key, confidence) = Self.ranked(Self.modelProbabilities(input))
        var changes: [(TimeInterval, MusicalKey, Double)] = []
        for segment in segments {
            guard let pitch = segment.pitch, let local = Self.modelInput([pitch]) else { continue }
            let (winner, certainty) = Self.ranked(Self.modelProbabilities(local))
            if changes.last?.1 != winner { changes.append((segment.timestamp, winner, certainty)) }
        }
        return (key, confidence, changes)
    }
}
