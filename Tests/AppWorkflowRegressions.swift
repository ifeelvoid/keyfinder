import AVFoundation
import Foundation
import KeyFinderEngine
import UniformTypeIdentifiers

@main
enum AppWorkflowRegressions {
    static func provider(_ url: URL?, delay: TimeInterval) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                if let url = url {
                    completion(url.dataRepresentation, nil)
                } else {
                    completion(nil, NSError(domain: "DropFixture", code: 1))
                }
            }
            return nil
        }
        return provider
    }

    @MainActor
    static func main() async throws {
        let first = URL(fileURLWithPath: "/tmp/first.WAV")
        let last = URL(fileURLWithPath: "/tmp/last.mp3")
        let urls = await AudioFileDropLoader.urls(from: [provider(first, delay: 0.1), provider(last, delay: 0)])
        precondition(urls == [first, last], "Out-of-order callbacks lost files or changed their order")
        let surviving = await AudioFileDropLoader.urls(from: [provider(first, delay: 0.1), provider(nil, delay: 0)])
        precondition(surviving == [first], "Failed last provider suppressed valid files")
        let filtered = await AudioFileDropLoader.urls(from: [provider(URL(fileURLWithPath: "/tmp/image.png"), delay: 0),
                                                            provider(URL(string: "https://example.com/audio.wav")!, delay: 0)])
        precondition(filtered.isEmpty, "Non-audio or remote URLs were accepted")
        let empty = await AudioFileDropLoader.urls(from: [])
        precondition(empty.isEmpty)
        print("PASS: file drops await all callbacks, retain order, survive errors and filter unsupported URLs")

        let suite = "KeyFinderStyleTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(KeyStyle.stored(in: defaults) == .trapHipHop, "Unset key style must default to Trap / Hip-Hop")
        defaults.set(KeyStyle.edm.rawValue, forKey: KeyStyle.storageKey)
        precondition(KeyStyle.stored(in: defaults) == .edm, "Stored EDM style must round trip")
        defaults.set("dubstep", forKey: KeyStyle.storageKey)
        precondition(KeyStyle.stored(in: defaults) == .trapHipHop, "Unknown stored style must fall back to the default")
        for style in KeyStyle.allCases {
            let detector = KeyDetector.configured(for: style)
            precondition(detector.style == KeyDetector.adoptedTemplates(for: style)
                         && detector.method == KeyDetector.adoptedMethod(for: style),
                         "Configured detector must use the selected style and its adopted method")
        }
        precondition(KeyStyle.edm.displayName == "EDM" && KeyStyle.trapHipHop.displayName == "Trap / Hip-Hop")
        print("PASS: key style defaults to Trap / Hip-Hop, persists, rejects unknown values and configures the detector")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeyFinderWorkflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = folder.appendingPathComponent("library.json")
        var saved = TrackAnalysis(fileName: "missing.wav", filePath: folder.appendingPathComponent("missing.wav"))
        saved.key = "Am"; saved.camelotNotation = "8A"; saved.bpm = "120"
        saved.detectedKey = "C"; saved.comment = "Keep my correction history"
        saved.cuePoints = [CuePoint(timestamp: 16, name: "Manual cue")]
        try JSONEncoder().encode([saved]).write(to: library)
        let model = AudioAnalysisModel(libraryURL: library)
        precondition(model.tracks[0].hasError && model.tracks[0].key == "Am")
        await model.retryFailedTracks()
        precondition(model.tracks[0].hasError && model.tracks[0].errorType == .fileNotFound,
                     "Bulk retry merely cleared the error instead of attempting analysis")
        precondition(model.tracks[0].key == nil && !model.tracks[0].isAnalyzing && !model.isAnalyzing)
        precondition(model.tracks[0].detectedKey == "C" && model.tracks[0].cuePoints[0].name == "Manual cue")
        precondition(model.tracks[0].comment == saved.comment)
        print("PASS: bulk retry reanalyzes stale keyed tracks and retains detected values, notes and manual cues")

        var fm = TrackAnalysis(fileName: "Trap Lords.wav", filePath: URL(fileURLWithPath: "/tmp/Trap Lords.wav"))
        fm.key = "Fm"; fm.camelotNotation = "4A"; fm.bpm = "170.7"
        precondition(AudioAnalysisModel.track(fm, matches: "4a"), "Camelot term missed its key")
        precondition(!AudioAnalysisModel.track(fm, matches: "14a") && !AudioAnalysisModel.track(fm, matches: "4b"),
                     "Camelot term matched a different key")
        precondition(AudioAnalysisModel.track(fm, matches: "140-175") && AudioAnalysisModel.track(fm, matches: "175-140"),
                     "BPM range missed an in-range track")
        precondition(!AudioAnalysisModel.track(fm, matches: "100-120"), "BPM range matched an out-of-range track")
        precondition(AudioAnalysisModel.track(fm, matches: "trap") && AudioAnalysisModel.track(fm, matches: "fm"))

        let importRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = importRoot.appendingPathComponent("Older/Dark", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: importRoot) }
        for path in ["b.wav", "Older/a.mp3", "Older/Dark/c.flac", "notes.txt", ".hidden.wav"] {
            FileManager.default.createFile(atPath: importRoot.appendingPathComponent(path).path, contents: Data())
        }
        let loose = importRoot.appendingPathComponent("b.wav")
        let expanded = AudioFileDropLoader.expandingFolders([importRoot, loose, importRoot.appendingPathComponent("notes.txt")])
            .map { $0.resolvingSymlinksInPath().path
                .replacingOccurrences(of: importRoot.resolvingSymlinksInPath().path + "/", with: "") }
        precondition(expanded == ["b.wav", "Older/a.mp3", "Older/Dark/c.flac", "b.wav"],
                     "Folder import order or filtering changed: \(expanded)")
        print("PASS: search matches names, exact Camelot keys and BPM ranges; folders expand to sorted audio files")

        let captureFolder = try LiveAudioCapture.captureFolder()
        precondition(FileManager.default.isWritableFile(atPath: captureFolder.path), "Capture folder is not writable")
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        let tone: [Float] = (0..<48000).map { (index: Int) -> Float in
            let phase: Double = Double(index) * 2.0 * Double.pi * 440.0 / 48000.0
            return Float(sin(phase) * 0.5)
        }
        try LiveAudioCapture.writeWAV(tone, sampleRate: 48000, to: wav)
        let readBack = try AVAudioFile(forReading: wav)
        precondition(readBack.length == 48000 && readBack.fileFormat.sampleRate == 48000
                     && readBack.fileFormat.channelCount == 1, "Saved capture is not the audio that was heard")
        print("PASS: live captures write readable mono WAVs to a writable folder")
    }
}
