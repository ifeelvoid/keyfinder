import Foundation
import AVFoundation
import KeyFinderEngine

public enum RegressionFixtures {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    public static func run() async throws -> [String] {
        var results: [String] = []
        let keys = KeyDetector.MusicalKey.allCases
        try require(keys.count == 24 && Set(keys.map(\.camelotNotation)).count == 24, "All 24 keys must map uniquely")
        try require(KeyDetector.MusicalKey.cMinor.camelotNotation == "5A" && KeyDetector.MusicalKey.aMinor.camelotNotation == "8A", "Known Camelot anchors")
        results.append("24 distinct Camelot mappings")

        func assessment(_ key: String, _ bpm: Double, _ energy: String = "Medium", _ direction: EnergyDirection = .hold) -> TransitionAssessment? {
            MixRanker.assess(fromKey: "8A", fromBPM: 120, fromEnergy: "Medium", toKey: key, toBPM: bpm, toEnergy: energy, direction: direction)
        }
        try require(assessment("8A", 120) != nil && assessment("8B", 121) != nil && assessment("9A", 123) != nil, "Same, relative and adjacent keys accepted")
        try require(assessment("2A", 120) == nil && assessment("8A", 140) == nil, "Clashes/extreme tempos rejected")
        try require(assessment("8A", .nan) == nil && assessment("0A", 120) == nil && assessment("8X", 120) == nil, "Invalid input rejected")
        try require(MixRanker.assess(fromKey: "12A", fromBPM: 120, fromEnergy: nil, toKey: "1A", toBPM: 120, toEnergy: nil) != nil, "Wheel wraparound")
        results.append("Harmonic compatibility, tempo bounds and invalid inputs")
        try require(assessment("8A", 120, "High", .lift)!.score > assessment("8A", 120, "Low", .lift)!.score, "Lift should prefer rising energy")
        try require(assessment("8A", 120, "Low", .ease)!.score > assessment("8A", 120, "High", .ease)!.score, "Ease should prefer lower energy")
        results.append("Energy-direction ranking")

        let envelope = [Double](repeating: 0.1, count: 32) + [Double](repeating: 0.9, count: 32) +
            [Double](repeating: 0.15, count: 32) + [Double](repeating: 0.8, count: 64)
        let downbeats = stride(from: 0.0, to: 80, by: 2).map { $0 }
        let cues = CuePlanner.suggest(envelope: envelope, interval: 0.5, duration: 80, downbeats: downbeats)
        try require(cues.count >= 4 && cues.count <= 8 && cues.allSatisfy { downbeats.contains($0.time) && $0.time < 80 }, "Beat-aligned bounded suggestions")
        try require(cues.contains { $0.name == "Energy rise" && abs($0.time - 16) <= 2 }, "Fixture energy rise at 16s")
        try require(cues.contains { $0.name == "Energy dip" && abs($0.time - 32) <= 2 }, "Fixture energy dip at 32s")
        try require(CuePlanner.suggest(envelope: envelope, interval: 0.5, duration: 80, downbeats: []).isEmpty, "No fake beat grid")
        results.append("Cue positions against known section changes")
        try require(CuePlanner.suggest(envelope: [Double](repeating: 0, count: 200), interval: 0.5, duration: 100, downbeats: downbeats).isEmpty, "Silence has no cues")
        try require(CuePlanner.suggest(envelope: [.nan], interval: 0, duration: 1, downbeats: downbeats).isEmpty, "Malformed envelopes fail closed")
        let encoded = try JSONEncoder().encode(cues)
        try require(try JSONDecoder().decode([CueSuggestion].self, from: encoded) == cues, "Cue round trip")
        results.append("Silent/invalid cues and JSON persistence")

        let specialName = "Artist \"A\" & <B>"
        let export = DJExportTrack(path: URL(fileURLWithPath: "/tmp/a & b # ü.wav"), name: specialName, artist: "A&B",
                                   key: "Am", bpm: 120, duration: 80,
                                   cues: [CueSuggestion(time: 16, name: specialName), CueSuggestion(time: -.infinity, name: "invalid")],
                                   firstDownbeat: 0, meter: "4/4")
        let xml = try XMLDocument(xmlString: DJExport.rekordbox([export]), options: [])
        let entries = try xml.nodes(forXPath: "/DJ_PLAYLISTS/COLLECTION/TRACK")
        try require(entries.count == 1 && (entries[0] as? XMLElement)?.attribute(forName: "Name")?.stringValue == specialName, "Rekordbox escaped metadata round trip")
        try require(try xml.nodes(forXPath: "//POSITION_MARK").count == 1, "Invalid cue omitted")
        try require(try xml.nodes(forXPath: "//POSITION_MARK/@Start").first?.stringValue == "16.000", "Rekordbox seconds")
        try require(try xml.nodes(forXPath: "//PLAYLISTS/NODE/NODE/TRACK/@Key").first?.stringValue == "1", "Numeric playlist links")
        let location = try xml.nodes(forXPath: "//COLLECTION/TRACK/@Location").first!.stringValue!
        try require(URL(string: location)?.path == export.path.path, "URI-encoded file paths round trip")
        results.append("Rekordbox XML structure, cues, escaping and URI paths")
        let nml = try XMLDocument(xmlString: DJExport.traktor([export]), options: [])
        try require(try nml.nodes(forXPath: "/NML/COLLECTION/ENTRY/CUE_V2/@START").first?.stringValue == "16000.000", "Traktor milliseconds")
        try require(try nml.nodes(forXPath: "//LOCATION/@DIR").first?.stringValue == "/:tmp/:", "Traktor directory syntax")
        results.append("Traktor NML structure and cue time units (not host-app import)")
        try require(DJExport.csv([["a,b", "x\"y", "two\nlines"]]) == "\"a,b\",\"x\"\"y\",\"two\nlines\"\r\n", "CSV quoting")
        results.append("CSV preserves punctuation and newlines")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyfinder-fixtures-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Over the old 180s slicing threshold, with an audible marker near the end.
        let fileURL = folder.appendingPathComponent("timeline.wav")
        try writeFixture(to: fileURL, duration: 190, rate: 48000) { time in
            time > 185 && time < 186 ? Float(0.5 * sin(2 * .pi * 440 * time)) : 0
        }
        let timeline = try AudioProcessor().readAnalysisAudio(at: fileURL)
        try require(abs(Double(timeline.samples.count) / timeline.sampleRate - 190) < 0.05, "Long-file timeline must not shrink")
        let late = timeline.samples[Int(185.2 * timeline.sampleRate)..<Int(185.8 * timeline.sampleRate)]
        try require(late.contains { abs($0) > 0.2 }, "Late marker must retain timestamp")
        results.append("190-second 48kHz file retains duration and late marker after resampling")

        let silent = folder.appendingPathComponent("silent.wav")
        try writeFixture(to: silent, duration: 3, rate: 22050) { _ in 0 }
        var rejected = false
        do { _ = try AudioProcessor().readAnalysisAudio(at: silent) } catch { rejected = true }
        try require(rejected, "Silent file must not receive a confident key")
        results.append("Silence fails with an analysis error")

        // Direct detector calls must not manufacture a key for absent or malformed audio.
        for samples: [Float] in [[], [Float](repeating: 0, count: 44100)] {
            var rejected = false
            do { _ = try await KeyDetector().detectKey(audioSamples: samples, sampleRate: 22050) }
            catch { rejected = true }
            try require(rejected, "Direct detector must reject empty/silent audio")
        }
        results.append("Direct key detector rejects absent audio")

        let rate = 22050.0
        let clicks: [Float] = (0..<Int(rate * 12)).map { sample in
            let phase = Double(sample).truncatingRemainder(dividingBy: rate / 2)
            return phase < 100 ? Float(exp(-phase / 20)) : 0
        }
        let tempo = try await BPMDetector().detectBPM(audioSamples: clicks, sampleRate: rate)
        try require(abs(tempo - 120) < 3, "120 BPM fixture measured \(tempo)")
        let grid = try await BeatGridDetector().detectBeatGrid(audioSamples: clicks, sampleRate: rate, detectedBPM: tempo)
        try require(!grid.beatGrid.beats.isEmpty && grid.beatGrid.beats.allSatisfy { $0.time >= 0 && $0.time < 12 }, "Beat times stay in original timeline")
        results.append("Synthetic 120 BPM pulse train and grid boundaries")
        let chord: [Float] = (0..<Int(rate * 6)).map { sample in
            let time = Double(sample) / rate
            return Float((sin(2 * .pi * 261.625565 * time) * 0.6 + sin(2 * .pi * 329.627557 * time) * 0.2 + sin(2 * .pi * 391.995436 * time) * 0.2) * 0.5)
        }
        let (key, confidence) = try await KeyDetector().detectKeyWithConfidence(audioSamples: chord, sampleRate: rate)
        try require(key == .cMajor, "C-major tonic fixture measured \(key.rawValue)")
        try require(confidence.isFinite && (0...1).contains(confidence), "Confidence must be bounded")
        results.append("Synthetic C-major triad and bounded confidence")
        results += try await detectorFixtures()
        results += try await BeatGridFixtures.run()
        results += try await TempoFixtures.run()
        return results
    }

    private static func detectorFixtures() async throws -> [String] {
        let rate = 22050.0
        let detector = KeyDetector()
        func triad(_ index: Int, base: Double = 261.625565, cents: Double = 0,
                   count: Int = 66150, gain: Double = 1, sampleRate: Double = 22050) -> [Float] {
            let root = base * pow(2, Double(index % 12) / 12 + cents / 1200)
            let third = root * pow(2, Double(index < 12 ? 4 : 3) / 12)
            let fifth = root * pow(2, 7.0 / 12)
            return (0..<count).map { sample in
                let time = Double(sample) / sampleRate
                return Float(gain * (0.3 * sin(2 * .pi * root * time) +
                                     0.1 * sin(2 * .pi * third * time) +
                                     0.1 * sin(2 * .pi * fifth * time)))
            }
        }
        for (index, expected) in KeyDetector.MusicalKey.allCases.enumerated() {
            let ordinary = try await detector.detectKey(audioSamples: triad(index), sampleRate: rate)
            try require(ordinary == expected, "Ordinary triad expected \(expected), received \(ordinary)")
            for cents in [-45.0, 0, 45.0] {
                let measured = try await detector.detectKey(audioSamples: triad(index, base: 1046.50226, cents: cents), sampleRate: rate)
                try require(measured == expected, "High triad expected \(expected) at \(cents) cents, received \(measured)")
            }
        }
        let reference = try await detector.detectKeyWithConfidence(audioSamples: triad(0), sampleRate: rate)
        for gain in [0.01, 1000000.0] {
            let measured = try await detector.detectKeyWithConfidence(audioSamples: triad(0, gain: gain), sampleRate: rate)
            try require(measured.0 == reference.0 && abs(measured.1 - reference.1) < 0.0001, "Global gain must not change key or confidence")
        }
        let exactFrame = try await detector.detectKey(audioSamples: triad(0, count: 32768), sampleRate: rate)
        try require(exactFrame == .cMajor, "Exactly one FFT frame must be analyzed")
        let shortFrame = try await detector.detectKey(audioSamples: triad(0, count: 8192), sampleRate: rate)
        try require(shortFrame == .cMajor, "Short valid audio must use a smaller FFT")
        let highRate = try await detector.detectKey(audioSamples: triad(0, count: 144000, sampleRate: 48000), sampleRate: 48000)
        try require(highRate == .cMajor, "48kHz detector input must retain pitch")

        for badRate in [0.0, -1, .nan, .infinity, 1e12] {
            var rejected = false
            do { _ = try await detector.detectKey(audioSamples: triad(0), sampleRate: badRate) }
            catch { rejected = true }
            try require(rejected, "Invalid sample rate must throw without trapping")
        }
        for invalid: [Float] in [[Float](repeating: .nan, count: 8192), [Float](repeating: .infinity, count: 8192), [1, 0]] {
            var rejected = false
            do { _ = try await detector.detectKey(audioSamples: invalid, sampleRate: rate) }
            catch { rejected = true }
            try require(rejected, "Malformed or undersized audio must throw")
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await detector.detectKey(audioSamples: triad(0), sampleRate: rate)
        }
        var cancellationReceived = false
        do { _ = try await cancelled.value } catch is CancellationError { cancellationReceived = true }
        try require(cancellationReceived, "Cancellation must propagate")

        let singleNote: [Float] = (0..<66150).map { Float(0.3 * sin(2 * .pi * 261.625565 * Double($0) / rate)) }
        let ambiguous = try await detector.detectKeyWithConfidence(audioSamples: singleNote, sampleRate: rate)
        try require(ambiguous.1 < reference.1, "A single note must be less certain than a tonic triad")
        var randomState: UInt64 = 0x12345678
        let noise: [Float] = (0..<66150).map { _ in
            randomState = randomState &* 6364136223846793005 &+ 1
            return Float(Double(randomState >> 32) / Double(UInt32.max) - 0.5)
        }
        do {
            let noisy = try await detector.detectKeyWithConfidence(audioSamples: noise, sampleRate: rate)
            try require(noisy.1 < reference.1, "Broadband noise must be less certain than a tonic triad")
        } catch KeyDetector.AnalysisError.noTonalEvidence {
            // Rejecting non-tonal audio is also a valid outcome.
        }
        let modulated = triad(0, count: Int(rate * 45)) + triad(4, count: Int(rate * 45))
        let changed = try await detector.detectKeyWithChanges(audioSamples: modulated, sampleRate: rate)
        try require(changed.2.contains { $0.1 == .cMajor } && changed.2.contains { $0.1 == .eMajor }, "Different tonal sections must survive aggregation")
        try require(changed.2.allSatisfy { $0.0 >= 0 && $0.0 < 90 && $0.2.isFinite && (0...1).contains($0.2) }, "Segment times and confidence remain bounded")
        try require(detector.spectralMode == .baseline, "Production detector must default to baseline spectral mode")
        for mode in [KeyDetector.SpectralMode.whitened, .whitenedHarmonic] {
            let measured = try await KeyDetector(spectralMode: mode).detectKeyWithConfidence(audioSamples: triad(0), sampleRate: rate)
            try require(measured.0 == .cMajor && measured.1.isFinite && (0...1).contains(measured.1),
                        "Experimental \(mode.rawValue) mode must keep a valid tonic-triad result")
        }
        let model = KeyDetector(method: .model)
        var modelTriads = 0
        for (index, expected) in KeyDetector.MusicalKey.allCases.enumerated() {
            let measured = try await model.detectKeyWithConfidence(audioSamples: triad(index), sampleRate: rate)
            try require(measured.1.isFinite && (0...1).contains(measured.1), "Model confidence must stay bounded")
            if measured.0 == expected { modelTriads += 1 }
        }
        try require(modelTriads == 24, "Key model must read all 24 tonic triads, read \(modelTriads)")
        for style in KeyStyle.allCases {
            let configured = KeyDetector.configured(for: style)
            try require(configured.method == KeyDetector.adoptedMethod(for: style)
                        && configured.style == KeyDetector.adoptedTemplates(for: style), "Style factory must match #0010 adoption")
        }
        return ["96 controlled triads across all keys, modes and tuning offsets",
                "Key model reads all 24 tonic triads; style factory matches #0010 adoption",
                "Gain invariance, short/exact frames and 48kHz pitch",
                "Invalid detector inputs and cancellation",
                "Noise/ambiguity lower confidence and differing key sections remain visible",
                "Baseline spectral mode is the default; #0005 experimental modes stay valid"]
    }

    private static func writeFixture(to url: URL, duration: Double, rate: Double, sample: (Double) -> Float) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768)!
        var offset = 0
        let total = Int(duration * rate)
        while offset < total {
            let count = min(32768, total - offset)
            buffer.frameLength = AVAudioFrameCount(count)
            for i in 0..<count { buffer.floatChannelData![0][i] = sample(Double(offset + i) / rate) }
            try file.write(from: buffer)
            offset += count
        }
    }
}
