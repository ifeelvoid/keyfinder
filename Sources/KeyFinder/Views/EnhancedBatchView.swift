import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Combine

/// Root window: top bar plus the FILES, LIVE and MIX screens
/// (layout from docs/briefs/0009-app-redesign/design-reference.pdf).
struct EnhancedBatchView: View {
    @StateObject private var model = AudioAnalysisModel()
    @StateObject private var liveCapture = LiveAudioCapture()
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("lastMode") private var lastMode: String = AppMode.files.rawValue
    @State private var mode: AppMode = .files
    @State private var isDragOver = false
    @State private var showHelp = false
    @State private var showAnalysisLog = false
    @State private var editingTagsTrackIndex: Int?
    @State private var editingCuesTrackIndex: Int?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar(mode: $mode, model: model, capture: liveCapture, searchFocus: $isSearchFocused,
                   onAddFiles: openFilePicker,
                   onShowLog: { showAnalysisLog = true },
                   onShowHelp: { showHelp = true })

            switch mode {
            case .files:
                HStack(spacing: 0) {
                    LibraryView(model: model, isDragOver: isDragOver, onAddFiles: openFilePicker,
                                onEditTags: { editingTagsTrackIndex = $0 },
                                onEditCues: { editingCuesTrackIndex = $0 })
                    if !model.tracks.isEmpty {
                        NowSelectedPanel(model: model)
                    }
                }
            case .live:
                LiveScreen(capture: liveCapture, onSave: { url in
                    Task { @MainActor in await model.addFiles([url]) }
                })
            case .mix:
                SmartDJPanel(model: model, embedded: true)
            }
        }
        .background(themeManager.backgroundColor.ignoresSafeArea())
        .frame(minWidth: 900, minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(commandNotifications) { handleNotification($0.name) }
        .onAppear {
            mode = AppMode(rawValue: lastMode) ?? .files
            if mode == .live { liveCapture.startCapture() }
            selectFirstTrackIfNeeded()
        }
        .onChange(of: mode) { newValue in
            lastMode = newValue.rawValue
            if newValue == .live {
                liveCapture.startCapture()
            } else {
                liveCapture.stopCapture()
            }
        }
        .onChange(of: model.tracks.count) { _ in selectFirstTrackIfNeeded() }
        .sheet(isPresented: $showHelp) {
            HelpView()
                .environmentObject(themeManager)
        }
        .sheet(item: Binding(
            get: { editingTagsTrackIndex.map { EditSheetIdentifier(index: $0) } },
            set: { editingTagsTrackIndex = $0?.index }
        )) { identifier in
            TagEditorView(track: $model.tracks[identifier.index])
                .environmentObject(themeManager)
        }
        .sheet(item: Binding(
            get: { editingCuesTrackIndex.map { EditSheetIdentifier(index: $0) } },
            set: { editingCuesTrackIndex = $0?.index }
        )) { identifier in
            CuePointsView(track: $model.tracks[identifier.index])
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showAnalysisLog) {
            AnalysisLogView(model: model)
                .environmentObject(themeManager)
                .frame(minWidth: 600, minHeight: 400)
        }
    }

    /// The side panel always has something to show once the library has tracks.
    private func selectFirstTrackIfNeeded() {
        let stillPresent = model.selectedTrack.map { selected in model.tracks.contains { $0.id == selected.id } } ?? false
        guard !stillPresent else { return }
        if let first = model.tracks.first(where: { $0.key != nil }) ?? model.tracks.first {
            model.selectTrackForHarmonicMixing(first)
        } else {
            model.clearSelection()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            let urls = await AudioFileDropLoader.urls(from: providers)
            await model.addFiles(AudioFileDropLoader.expandingFolders(urls))
        }
        return true
    }

    // SwiftUI owns these subscriptions and tears them down with the view.
    private var commandNotifications: Publishers.MergeMany<NotificationCenter.Publisher> {
        let names: [Notification.Name] = [
            .openFiles, .exportTracks, .focusSearch, .showHelp, .showAnalysisLog,
            .exportRekordbox, .exportSerato, .exportTraktor, .exportEngineDJ,
            .exportVirtualDJ, .exportiTunes, .exportMetadataPlan
        ]
        return Publishers.MergeMany(names.map { NotificationCenter.default.publisher(for: $0) })
    }

    private func handleNotification(_ name: Notification.Name) {
        switch name {
        case .openFiles: openFilePicker()
        case .focusSearch: isSearchFocused = true
        case .showHelp: showHelp = true
        case .showAnalysisLog: showAnalysisLog = true
        default:
            guard !model.tracks.isEmpty || name == .exportMetadataPlan else { return }
            let url: URL?
            switch name {
            case .exportTracks: url = model.exportToCSV()
            case .exportRekordbox: url = model.exportToRekordbox()
            case .exportSerato: url = model.exportToSerato()
            case .exportTraktor: url = model.exportToTraktor()
            case .exportEngineDJ: url = model.exportToEngineDJ()
            case .exportVirtualDJ: url = model.exportToVirtualDJ()
            case .exportiTunes: url = model.exportToiTunes()
            case .exportMetadataPlan: url = model.exportMetadataPlan()
            default: return
            }
            if let url = url {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .audio,
            .mp3,
            .wav,
            .aiff
        ]
        panel.message = "Select audio files or folders to analyze"

        if panel.runModal() == .OK {
            let urls = AudioFileDropLoader.expandingFolders(panel.urls)
            Task {
                await model.addFiles(urls)
            }
        }
    }

}

struct EditSheetIdentifier: Identifiable {
    let index: Int
    var id: Int { index }
}

struct ExpandedWaveformView: View {
    let track: TrackAnalysis
    @EnvironmentObject var themeManager: ThemeManager
    @State private var waveformData: [Float] = []
    @State private var duration: TimeInterval = 0
    @State private var currentPosition: TimeInterval = 0

    private let targetSamples = 200

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.tertiaryTextColor)
                Text("WAVEFORM WITH BEATGRID")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)

                if let bpm = track.beatGrid?.bpm {
                    Text("• \(Int(bpm)) BPM")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }

                if let timeSig = track.beatGrid?.timeSignature {
                    Text("• \(timeSig)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }

                Spacer()

                Text("\(formatTime(currentPosition)) / \(formatTime(duration))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }

            // Waveform with beatgrid overlay
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(themeManager.surfaceColor)
                        .frame(height: 80)
                        .cornerRadius(4)

                    // Waveform bars
                    HStack(spacing: 1) {
                        ForEach(Array(waveformData.enumerated()), id: \.offset) { index, amplitude in
                            let xPosition = CGFloat(index) / CGFloat(max(1, waveformData.count - 1)) * geometry.size.width
                            let isPlayed = duration > 0 && (CGFloat(currentPosition) / CGFloat(duration)) * geometry.size.width >= xPosition

                            Rectangle()
                                .fill(isPlayed ? themeManager.textColor : themeManager.tertiaryTextColor.opacity(0.4))
                                .frame(width: max(1, geometry.size.width / CGFloat(waveformData.count) - 1))
                                .frame(height: max(2, CGFloat(amplitude) * 70))
                        }
                    }
                    .frame(height: 70, alignment: .center)

                    // Beatgrid overlay
                    if let grid = track.beatGrid, grid.hasValidGrid {
                        BeatGridOverlayView(beatGrid: grid, duration: duration, currentPosition: $currentPosition)
                    }

                    // Playhead
                    if duration > 0 {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 2)
                            .offset(x: playheadPosition(in: geometry.size.width))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let position = max(0, min(value.location.x, geometry.size.width))
                            currentPosition = (position / geometry.size.width) * duration
                        }
                )
            }
            .frame(height: 80)

            // Beatgrid legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: 10)
                    Text("Downbeat")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }

                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 1, height: 10)
                    Text("Beat")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }

                Spacer()

                if let grid = track.beatGrid {
                    Text("Total beats: \(grid.beats.count)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }
            }
        }
        .padding(12)
        .background(themeManager.surfaceColor.opacity(0.5))
        .cornerRadius(4)
        .onAppear {
            loadAudioData()
        }
    }

    private func playheadPosition(in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return (currentPosition / duration) * width
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func loadAudioData() {
        let filePath = track.filePath
        let samples = targetSamples

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let audioFile = try AVAudioFile(forReading: filePath)
                let format = audioFile.processingFormat
                let sampleRate = format.sampleRate
                let frameCount = AVAudioFrameCount(audioFile.length)

                let duration = Double(frameCount) / sampleRate
                let step = max(1, Int(frameCount) / samples)

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return }

                var waveform: [Float] = []

                for i in stride(from: 0, to: Int(frameCount), by: step) {
                    audioFile.framePosition = AVAudioFramePosition(i)
                    let framesToRead = AVAudioFrameCount(min(4096, Int(frameCount) - i))

                    do {
                        try audioFile.read(into: buffer, frameCount: framesToRead)
                    } catch {
                        continue
                    }

                    guard let floatData = buffer.floatChannelData else { continue }

                    var sum: Float = 0
                    var peak: Float = 0
                    let actualFrames = Int(buffer.frameLength)

                    for j in 0..<actualFrames {
                        let sample = abs(floatData[0][j])
                        sum += sample * sample
                        if sample > peak { peak = sample }
                    }

                    // Combine RMS and peak for better visualization
                    let rms = sqrt(sum / Float(actualFrames))
                    let combined = (rms + peak) / 2.0
                    waveform.append(combined)
                }

                if let maxValue = waveform.max(), maxValue > 0 {
                    waveform = waveform.map { min(1.0, $0 / maxValue * 1.2) }

                    DispatchQueue.main.async {
                        self.waveformData = waveform
                        self.duration = duration
                    }
                }
            } catch {
                // Silently fail
            }
        }
    }
}
