import Foundation
import Testing
@testable import KeyFinderEngine

private func track(_ name: String, _ camelot: String, _ bpm: Double, energy: Int = 1) -> TrackSummary {
    TrackSummary(path: "/music/\(name).wav", fileName: "\(name).wav", key: "", camelot: camelot,
                 bpm: bpm, confidence: 0.9, energy: "", energyRank: energy, duration: 300, keyChanges: [])
}

@Suite("Camelot")
struct CamelotTests {
    @Test("Parses valid notation", arguments: ["8A", "08a", " 12B ", "1b"])
    func parses(text: String) {
        #expect(CamelotKey(text) != nil)
    }

    @Test("Rejects invalid notation", arguments: ["", "8", "13A", "0B", "8C", "AA"])
    func rejects(text: String) {
        #expect(CamelotKey(text) == nil)
    }

    @Test("Wheel matches the engine's key table for all 24 keys")
    func tonicMatchesKeyTable() {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let keys: [KeyDetector.MusicalKey] = [
            .cMajor, .cSharpMajor, .dMajor, .dSharpMajor, .eMajor, .fMajor, .fSharpMajor, .gMajor,
            .gSharpMajor, .aMajor, .aSharpMajor, .bMajor, .cMinor, .cSharpMinor, .dMinor, .dSharpMinor,
            .eMinor, .fMinor, .fSharpMinor, .gMinor, .gSharpMinor, .aMinor, .aSharpMinor, .bMinor,
        ]
        for key in keys {
            let tonic = String(key.rawValue.split(separator: " ")[0])
            #expect(names[CamelotKey(key).tonicPitchClass] == tonic, "\(key.rawValue)")
        }
    }

    @Test("Compatibility wraps around the wheel")
    func compatibilityWraps() {
        let key = CamelotKey("12A")!
        #expect(key.compatibleKeys.map(\.description) == ["12A", "11A", "1A", "12B"])
        #expect(key.relation(to: CamelotKey("1A")!) == .energyUp)
        #expect(key.relation(to: CamelotKey("5A")!) == nil)
    }

    @Test("Tempo distance treats half and double time as matches")
    func tempoHalfDouble() {
        #expect(TempoMatch.distancePercent(from: 140, to: 70) == 0)
        #expect(TempoMatch.distancePercent(from: 85, to: 170) == 0)
        #expect(abs(TempoMatch.distancePercent(from: 124, to: 128) - 3.2258) < 0.001)
    }
}

@Suite("Sample fit")
struct SampleFitTests {
    @Test("Shortest transpose, wrapping both ways")
    func shortestShift() {
        // A minor loop into B minor project: up 2.
        let up = SampleFit.compute(sampleKey: CamelotKey("8A")!, sampleBPM: 124,
                                   targetKey: CamelotKey("10A")!, targetBPM: 124)
        #expect(up.semitoneShift == 2)
        // B minor loop into A minor project: down 2, not up 10.
        let down = SampleFit.compute(sampleKey: CamelotKey("10A")!, sampleBPM: 124,
                                     targetKey: CamelotKey("8A")!, targetBPM: 124)
        #expect(down.semitoneShift == -2)
    }

    @Test("Neighbouring key is flagged as already compatible")
    func neighbourCompatible() {
        let fit = SampleFit.compute(sampleKey: CamelotKey("9A")!, sampleBPM: 126,
                                    targetKey: CamelotKey("8A")!, targetBPM: 124)
        #expect(fit.compatibleWithoutShift == HarmonicRelation.energyDown.rawValue)
        #expect(fit.semitoneShift == 5)
        let clash = SampleFit.compute(sampleKey: CamelotKey("2B")!, sampleBPM: 126,
                                      targetKey: CamelotKey("8A")!, targetBPM: 124)
        #expect(clash.compatibleWithoutShift == nil)
    }

    @Test("Relative key needs no transpose")
    func relativeKey() {
        let fit = SampleFit.compute(sampleKey: CamelotKey("8A")!, sampleBPM: 120,
                                    targetKey: CamelotKey("8B")!, targetBPM: 120)
        #expect(fit.semitoneShift == 0)
        #expect(fit.keyAfterShift == CamelotKey("8A")!)
        #expect(!fit.notes.isEmpty)
    }

    @Test("Half-time and double-time are chosen over large stretches")
    func tempoModes() {
        let half = SampleFit.compute(sampleKey: CamelotKey("8A")!, sampleBPM: 70,
                                     targetKey: CamelotKey("8A")!, targetBPM: 140)
        #expect(half.tempoMode == .halfTime)
        #expect(half.timeStretchRatio == 1)
        let double = SampleFit.compute(sampleKey: CamelotKey("8A")!, sampleBPM: 174,
                                       targetKey: CamelotKey("8A")!, targetBPM: 87)
        #expect(double.tempoMode == .doubleTime)
        let stretch = SampleFit.compute(sampleKey: CamelotKey("8A")!, sampleBPM: 120,
                                        targetKey: CamelotKey("8A")!, targetBPM: 124)
        #expect(stretch.tempoMode == .normal)
        #expect(abs(stretch.timeStretchRatio - 124.0 / 120.0) < 1e-4)
        let encoded = String(decoding: try! JSONEncoder().encode(stretch), as: UTF8.self)
        #expect(encoded.contains(#""keyAfterShift":"8A""#))
    }
}

@Suite("Harmonic mixer")
struct HarmonicMixerTests {
    let library = [
        track("a", "8A", 124, energy: 0), track("b", "9A", 125, energy: 1), track("c", "8B", 124, energy: 2),
        track("d", "3A", 124, energy: 3), track("e", "8A", 140, energy: 2), track("f", "7A", 62, energy: 1),
    ]

    @Test("Compatible tracks: harmonic, within tempo, best first, excluding the reference")
    func compatible() {
        let matches = HarmonicMixer.compatible(with: CamelotKey("8A")!, bpm: 124, energyRank: 0,
                                               excludingPath: "/music/a.wav", in: library)
        #expect(matches.map(\.track.fileName) == ["c.wav", "f.wav", "b.wav"])
        #expect(matches.allSatisfy { $0.bpmDeltaPercent <= 6 })
        #expect(matches[0].relation == HarmonicRelation.relative.rawValue)
    }

    @Test("Build set is deterministic, unique, and respects maxTracks")
    func buildSetDeterministic() {
        let first = HarmonicMixer.buildSet(from: library, maxTracks: 4, shape: .build)
        let second = HarmonicMixer.buildSet(from: library.reversed(), maxTracks: 4, shape: .build)
        #expect(first.map(\.track.path) == second.map(\.track.path))
        #expect(first.count == 4)
        #expect(Set(first.map(\.track.path)).count == 4)
        #expect(first[0].track.fileName == "a.wav")
        #expect(first[0].transition == nil)
        #expect(first.dropFirst().allSatisfy { $0.transition != nil })
    }

    @Test("A clash is labelled when nothing compatible is left")
    func clashLabelled() {
        let set = HarmonicMixer.buildSet(from: [track("x", "1A", 120), track("y", "6B", 120)], maxTracks: 2)
        #expect(set.count == 2)
        #expect(set[1].transition?.contains("key clash") == true)
    }

    @Test("Peak shape targets the top two-thirds in")
    func peakCurve() {
        let peak = HarmonicMixer.targetEnergy(position: 6, length: 10, shape: .peak, openerRank: 0)
        let end = HarmonicMixer.targetEnergy(position: 9, length: 10, shape: .peak, openerRank: 0)
        #expect(peak == 3)
        #expect(end == 0)
    }

    @Test("Empty library yields an empty set")
    func emptyLibrary() {
        #expect(HarmonicMixer.buildSet(from: []).isEmpty)
    }
}

@Suite("Analysis cache")
struct AnalysisCacheTests {
    @Test("Round-trips and invalidates when the file changes")
    func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = AnalysisCache(directory: dir.appendingPathComponent("cache"))
        let file = dir.appendingPathComponent("song.wav")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: file)

        let summary = track("song", "8A", 124)
        #expect(cache.load(for: file) == nil)
        cache.store(summary, for: file)
        #expect(cache.load(for: file) == summary)

        try Data([1, 2, 3, 4]).write(to: file)
        #expect(cache.load(for: file) == nil)
    }
}

@Suite("AI folder access")
struct AIFolderAccessTests {
    private func store() -> (AIFolderAccess, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kf-access-\(UUID().uuidString)")
        return (AIFolderAccess(fileURL: dir.appendingPathComponent("KeyFinder/ai-folders.json")), dir)
    }

    @Test("No saved list falls back to ~/Music")
    func defaults() {
        let (access, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(access.load() == nil)
        #expect(access.effectiveFolders() == AIFolderAccess.defaultFolders)
    }

    @Test("Save normalizes, de-duplicates, keeps order, and round-trips")
    func roundTrip() throws {
        let (access, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try access.save(["/Volumes/DJ USB/", "~/Splice", " ", "/Volumes/DJ USB", "relative/path", "/tmp/../tmp/x"])
        let home = NSHomeDirectory()
        #expect(access.load() == ["/Volumes/DJ USB", home + "/Splice", "/tmp/x"])
    }

    @Test("An empty saved list stays empty (user removed every folder)")
    func emptyList() throws {
        let (access, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try access.save([])
        #expect(access.load() == [])
        #expect(access.effectiveFolders().isEmpty)
    }

    @Test("A corrupt file is treated as no saved list")
    func corrupt() throws {
        let (access, dir) = store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: access.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: access.fileURL)
        #expect(access.load() == nil)
    }
}
