import Foundation
import CryptoKit

/// Codable, UI-free snapshot of one analyzed track. This is what the MCP server returns
/// and what the engine cache stores.
public struct TrackSummary: Codable, Equatable, Sendable {
    public struct KeyChange: Codable, Equatable, Sendable {
        public let time: TimeInterval
        public let key: String
        public let camelot: String
        public let confidence: Double
    }

    public let path: String
    public let fileName: String
    public let key: String
    public let camelot: String
    public let bpm: Double
    public let confidence: Double
    public let energy: String
    /// 0 = Low ... 3 = Very High; used for set energy curves.
    public let energyRank: Int
    public let duration: TimeInterval
    public let keyChanges: [KeyChange]

    public init(path: String, fileName: String, key: String, camelot: String, bpm: Double,
                confidence: Double, energy: String, energyRank: Int, duration: TimeInterval,
                keyChanges: [KeyChange]) {
        self.path = path
        self.fileName = fileName
        self.key = key
        self.camelot = camelot
        self.bpm = bpm
        self.confidence = confidence
        self.energy = energy
        self.energyRank = energyRank
        self.duration = duration
        self.keyChanges = keyChanges
    }

    public init(result: AudioProcessor.AnalysisResult, path: String) {
        self.init(
            path: path,
            fileName: result.fileName,
            key: result.key.rawValue,
            camelot: result.key.camelotNotation,
            bpm: (result.bpm * 10).rounded() / 10,
            confidence: (result.confidence * 100).rounded() / 100,
            energy: result.energy.rawValue,
            energyRank: Self.rank(of: result.energy),
            duration: result.duration.rounded(),
            keyChanges: result.keyChanges.map { time, key, confidence in
                KeyChange(time: time.rounded(), key: key.rawValue,
                          camelot: key.camelotNotation, confidence: confidence)
            }
        )
    }

    public var camelotKey: CamelotKey? { CamelotKey(camelot) }

    static func rank(of energy: AudioProcessor.EnergyLevel) -> Int {
        switch energy {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .veryHigh: return 3
        }
    }
}

/// On-disk analysis cache keyed by file path, invalidated when size or modification date
/// changes. Separate from the app's own cache so the MCP server never depends on app code.
public struct AnalysisCache: Sendable {
    private struct Entry: Codable {
        let size: Int64
        let modified: Date
        let summary: TrackSummary
    }

    public let directory: URL

    public init(directory: URL = AnalysisCache.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("com.ifeelvoid.keyfinder/analysis-v1", isDirectory: true)
    }

    public func load(for url: URL) -> TrackSummary? {
        guard let stamp = Self.stamp(of: url),
              let data = try? Data(contentsOf: entryURL(for: url)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.size == stamp.size, entry.modified == stamp.modified else { return nil }
        return entry.summary
    }

    /// Best-effort: a failed cache write must never fail an analysis.
    public func store(_ summary: TrackSummary, for url: URL) {
        guard let stamp = Self.stamp(of: url) else { return }
        let entry = Entry(size: stamp.size, modified: stamp.modified, summary: summary)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: entryURL(for: url), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("keyfinder: cache write failed: \(error.localizedDescription)\n".utf8))
        }
    }

    private func entryURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).json")
    }

    private static func stamp(of url: URL) -> (size: Int64, modified: Date)? {
        // Read attributes from disk each time: URL.resourceValues caches per URL value and
        // would keep serving a stale size after the file is re-exported in place.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return (size, modified)
    }
}
