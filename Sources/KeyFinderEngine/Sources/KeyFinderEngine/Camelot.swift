import Foundation

/// A position on the Camelot wheel ("8A" = A minor, "8B" = C major).
///
/// Shared by the app's Smart DJ features and the MCP server so both agree on what
/// "compatible" means.
public struct CamelotKey: Hashable, Codable, CustomStringConvertible {
    public enum Mode: String, Codable {
        case minor = "A"
        case major = "B"
    }

    public let number: Int
    public let mode: Mode

    public init?(number: Int, mode: Mode) {
        guard (1...12).contains(number) else { return nil }
        self.number = number
        self.mode = mode
    }

    /// Parses "8A", "08a", " 12B ". Returns nil for anything else.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard let letter = trimmed.last,
              let mode = Mode(rawValue: String(letter)),
              let number = Int(trimmed.dropLast()) else { return nil }
        self.init(number: number, mode: mode)
    }

    public init(_ key: KeyDetector.MusicalKey) {
        // camelotNotation is a fixed table of valid values, so parsing cannot fail.
        self = CamelotKey(key.camelotNotation)!
    }

    public var description: String { "\(number)\(mode.rawValue)" }

    /// Encoded as the familiar "8A" string, not an object.
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = CamelotKey(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Camelot key \(text)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Pitch class of the tonic, 0 = C ... 11 = B.
    /// The wheel is the circle of fifths: 8B is C, each step clockwise adds a fifth (7
    /// semitones). A relative minor's tonic sits 9 semitones above its major.
    public var tonicPitchClass: Int {
        let majorTonic = Self.wrap12((number - 8) * 7)
        return mode == .major ? majorTonic : Self.wrap12(majorTonic + 9)
    }

    public var relative: CamelotKey {
        CamelotKey(number: number, mode: mode == .major ? .minor : .major)!
    }

    public func stepped(by offset: Int) -> CamelotKey {
        CamelotKey(number: Self.wrap12(number - 1 + offset) + 1, mode: mode)!
    }

    /// How a mix from `self` into `other` works harmonically, or nil if it clashes.
    public func relation(to other: CamelotKey) -> HarmonicRelation? {
        if other == self { return .sameKey }
        if other == relative { return .relative }
        if other == stepped(by: 1) { return .energyUp }
        if other == stepped(by: -1) { return .energyDown }
        return nil
    }

    /// The four keys a DJ can mix into from `self` without clashing.
    public var compatibleKeys: [CamelotKey] {
        [self, stepped(by: -1), stepped(by: 1), relative]
    }

    static func wrap12(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }
}

public enum HarmonicRelation: String, Codable {
    case sameKey = "same key"
    case relative = "relative major/minor"
    case energyUp = "+1 (energy up)"
    case energyDown = "-1 (energy down)"

    /// Ranking weight used when several compatible tracks are available.
    public var score: Double {
        switch self {
        case .sameKey: return 1.0
        case .relative: return 0.9
        case .energyUp, .energyDown: return 0.85
        }
    }
}

/// Tempo comparison that treats half- and double-time as the same groove.
public enum TempoMatch {
    /// Smallest percentage distance from `reference` to `bpm`, `bpm * 2` or `bpm / 2`.
    public static func distancePercent(from reference: Double, to bpm: Double) -> Double {
        guard reference > 0, bpm > 0 else { return .infinity }
        return [bpm, bpm * 2, bpm / 2]
            .map { abs($0 - reference) / reference * 100 }
            .min() ?? .infinity
    }
}
