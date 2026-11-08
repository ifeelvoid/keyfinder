import Foundation
import CryptoKit
import KeyFinderEngine

// Brief #0011: runs every BPMDetector method on a frozen truth split. Audio is read only.
// Usage: KeyFinderTempoBench <split.json> <out.json>
struct Song: Codable { let id: String; let family: String; let tempo: Double; let path: String }
struct Row: Codable {
    let id: String
    let family: String
    let tempo: Double
    let audioSHA256: String?
    let estimates: [String: Double]
    let error: String?
}
struct Run: Codable {
    let split: String
    let splitSHA256: String
    let executableSHA256: String
    let methods: [String]
    let rows: [Row]
}

func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: KeyFinderTempoBench <split.json> <out.json>\n".data(using: .utf8)!)
    exit(2)
}
let splitURL = URL(fileURLWithPath: args[1])
let songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: splitURL))
var rows = [Row]()
for (index, song) in songs.enumerated() {
    let url = URL(fileURLWithPath: song.path)
    do {
        let hash = try sha256(url)
        let audio = try AudioProcessor().readAnalysisAudio(at: url)
        var estimates = [String: Double]()
        for method in BPMDetector.Method.allCases {
            estimates[method.rawValue] = try await BPMDetector(method: method)
                .detectBPM(audioSamples: audio.samples, sampleRate: audio.sampleRate)
        }
        rows.append(Row(id: song.id, family: song.family, tempo: song.tempo, audioSHA256: hash, estimates: estimates, error: nil))
        print("\(index + 1)/\(songs.count) \(song.family) \(song.tempo) \(estimates)")
    } catch {
        rows.append(Row(id: song.id, family: song.family, tempo: song.tempo, audioSHA256: nil, estimates: [:], error: "\(error)"))
        print("\(index + 1)/\(songs.count) \(song.family) error \(error)")
    }
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let run = Run(split: splitURL.lastPathComponent, splitSHA256: try sha256(splitURL),
              executableSHA256: try sha256(URL(fileURLWithPath: args[0])),
              methods: BPMDetector.Method.allCases.map(\.rawValue), rows: rows)
try encoder.encode(run).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
