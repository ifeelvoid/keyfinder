import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct EnhancedBatchView: View {
    @StateObject private var model = AudioAnalysisModel()
    @StateObject private var liveCapture = LiveAudioCapture()
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("lastMode") private var lastMode: String = "live"
    @State private var selectedMode: String = "live"
    @State private var isDragOver = false
    @State private var showHelp = false
    @State private var showCamelotWheel = false
    @State private var showAnalysisLog = false
    @State private var editingTagsTrackIndex: Int?
    @State private var editingCuesTrackIndex: Int?
    @State private var expandedTrackIndex: Int?  // Track with expanded waveform
    @State private var showSmartDJPanel = false
    @State private var showDuplicatesPanel = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar
                tabBar

                // Content based on selected mode
                if selectedMode == "live" {
                    LiveInputView(capture: liveCapture)
                } else {
                    // File mode content
                    VStack(spacing: 0) {
                        // Header with search and export
                        headerView

                        if model.tracks.isEmpty {
                            dropZoneView
                        } else {
                            VStack(spacing: 0) {
                                // Search and filter bar
                                searchFilterBar

                                // Track list
                                trackListView
                            }
                        }
                    }
                }
            }

            // Camelot Wheel overlay (bottom right)
            if showCamelotWheel && !model.tracks.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        camelotWheelOverlay
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            selectedMode = lastMode
            setupNotificationObservers()
            // Auto-start live capture on first launch
            if selectedMode == "live" && !liveCapture.isCapturing {
                liveCapture.startCapture()
            }
        }
        .onChange(of: selectedMode) { newValue in
            lastMode = newValue
            if newValue == "live" && !liveCapture.isCapturing {
                liveCapture.startCapture()
            } else if newValue == "file" {
                liveCapture.stopCapture()
            }
        }
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
        // .sheet(isPresented: $showSmartDJPanel) {
        //     SmartDJPanel(model: model)
        //         .environmentObject(themeManager)
        //         .frame(minWidth: 700, minHeight: 500)
        // }
        // .sheet(isPresented: $showDuplicatesPanel) {
        //     DuplicatesPanel(model: model)
        //         .environmentObject(themeManager)
        //         .frame(minWidth: 700, minHeight: 500)
        // }
    }

    private var headerView: some View {
        HStack {
            Text("KEY FINDER")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.textColor)

            Spacer()

            // Camelot Wheel button
            if !model.tracks.isEmpty {
                Button(action: { showCamelotWheel.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 10))
                        Text("WHEEL")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(themeManager.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }

            // Theme toggle
            Menu {
                ForEach(ThemeManager.Theme.allCases, id: \.self) { theme in
                    Button(action: { themeManager.currentTheme = theme }) {
                        HStack {
                            Text(theme.rawValue)
                            if themeManager.currentTheme == theme {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: themeManager.currentTheme == .dark ? "moon.fill" : (themeManager.currentTheme == .light ? "sun.max.fill" : "circle.lefthalf.filled"))
                        .font(.system(size: 10))
                    Text("THEME")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(themeManager.secondaryTextColor)
            }
            .menuStyle(.borderlessButton)

            Spacer()

            if !model.tracks.isEmpty {
                // Export dropdown menu
                Menu {
                    Button(action: {
                        if let url = model.exportToCSV() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Export CSV")
                        Image(systemName: "tablecells")
                    }

                    Button(action: {
                        if let url = model.exportToRekordbox() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Export Rekordbox XML")
                        Image(systemName: "music.note.list")
                    }

                    Button(action: {
                        if let url = model.exportToSerato() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Export Serato CSV")
                        Image(systemName: "waveform")
                    }

                    Button(action: {
                        if let url = model.exportToTraktor() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Export Traktor NML")
                        Image(systemName: "square.and.arrow.up")
                    }

                    Button(action: {
                        if let url = model.exportToEngineDJ() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Export Engine DJ")
                        Image(systemName: "doc.badge.arrow.up")
                    }

                    Button(action: {
                        if let url = model.exportToVirtualDJ() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Export Virtual DJ")
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }

                    Button(action: {
                        if let url = model.exportToiTunes() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Export iTunes XML")
                        Image(systemName: "music.note.list")
                    }

                    Divider()

                    Button(action: {
                        if let url = model.writeTagsToFiles() {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Text("Write Tags to Files")
                        Image(systemName: "tag")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("EXPORT")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.secondaryTextColor)
                }
                .menuStyle(.borderlessButton)

                // Error handling buttons
                if model.failedTracksCount > 0 {
                    Button(action: {
                        Task { @MainActor in
                            await model.retryFailedTracks()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("RETRY FAILED (\(model.failedTracksCount))")
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isAnalyzing)

                    Button(action: {
                        model.skipFailedTracks()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                            Text("SKIP (\(model.failedTracksCount))")
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                    }
                    .buttonStyle(.plain)
                }

                // Smart DJ Panel button - temporarily disabled for v1.7
                // if !model.tracks.isEmpty {
                //     Button(action: { showSmartDJPanel = true }) {
                //         HStack(spacing: 4) {
                //             Image(systemName: "music.note.list")
                //             Text("MIX")
                //         }
                //         .font(.system(size: 10, weight: .medium, design: .monospaced))
                //         .foregroundColor(themeManager.secondaryTextColor)
                //     }
                //     .buttonStyle(.plain)

                //     // Duplicates button with badge if duplicates found
                //     Button(action: { showDuplicatesPanel = true }) {
                //         HStack(spacing: 4) {
                //             Image(systemName: "doc.on.doc")
                //             Text("DUPES")
                //             if model.duplicateGroups.count > 0 {
                //                 Text("(\(model.duplicateGroups.count))")
                //                     .foregroundColor(.orange)
                //             }
                //         }
                //         .font(.system(size: 10, weight: .medium, design: .monospaced))
                //         .foregroundColor(model.duplicateGroups.isEmpty ? themeManager.secondaryTextColor : .orange)
                //     }
                //     .buttonStyle(.plain)
                // }

                // Show Analysis Log button
                Button(action: { showAnalysisLog = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text("LOG")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.secondaryTextColor)
                }
                .buttonStyle(.plain)

                Button(action: { model.clearAll() }) {
                    Text("CLEAR ALL")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            // LIVE tab
            Button(action: {
                selectedMode = "live"
            }) {
                Text("LIVE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(selectedMode == "live" ? .white : themeManager.tertiaryTextColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        selectedMode == "live" ?
                        themeManager.accentColorSubtle :
                        Color.clear
                    )
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // FILE tab
            Button(action: {
                selectedMode = "file"
            }) {
                Text("FILE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(selectedMode == "file" ? .white : themeManager.tertiaryTextColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        selectedMode == "file" ?
                        themeManager.accentColorSubtle :
                        Color.clear
                    )
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 15)
        .padding(.bottom, 5)
        .background(themeManager.backgroundColor)
    }

    private var searchFilterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(themeManager.tertiaryTextColor)
                        .font(.system(size: 10))
                    TextField("Search tracks...", text: $model.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                        .focused($isSearchFocused)
                }
                .padding(8)
                .background(themeManager.surfaceColor)
                .cornerRadius(2)

                // BPM range
                Text("BPM:")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)

                HStack(spacing: 4) {
                    TextField("Min", value: $model.filterBPMMin, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                        .frame(width: 40)
                    Text("-")
                        .foregroundColor(themeManager.tertiaryTextColor)
                    TextField("Max", value: $model.filterBPMMax, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                        .frame(width: 40)
                }
                .padding(6)
                .background(themeManager.surfaceColor)
                .cornerRadius(2)

                if model.searchText != "" || model.filterBPMMin != nil || model.filterBPMMax != nil {
                    Button(action: {
                        model.searchText = ""
                        model.filterBPMMin = nil
                        model.filterBPMMax = nil
                    }) {
                        Text("CLEAR")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(model.filteredTracks.count) tracks")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(themeManager.surfaceColor.opacity(0.4))
    }

    private var trackListView: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 12) {
                Text("ART")
                    .frame(width: 50)
                Text("TRACK")
                    .frame(width: 160, alignment: .leading)
                Text("KEY")
                    .frame(width: 35)
                Text("CAMELOT")
                    .frame(width: 50)
                Text("BPM")
                    .frame(width: 50)
                Text("DUR")
                    .frame(width: 45)
                Text("WAVEFORM")
                    .frame(width: 100)
                Spacer()
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(themeManager.tertiaryTextColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Rectangle()
                .fill(themeManager.borderColor)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.filteredTracks.enumerated()), id: \.element.id) { index, track in
                        EnhancedTrackRow(
                            track: track,
                            isSelected: model.selectedTrack?.id == track.id,
                            onSelect: { model.selectTrackForHarmonicMixing(track) },
                            onRemove: {
                                if let idx = model.tracks.firstIndex(where: { $0.id == track.id }) {
                                    model.removeTrack(at: idx)
                                }
                            },
                            onAlbumArtUpdate: { newImage in
                                if let idx = model.tracks.firstIndex(where: { $0.id == track.id }) {
                                    model.updateAlbumArt(at: idx, image: newImage)
                                }
                            },
                            onEditTags: {
                                if let idx = model.tracks.firstIndex(where: { $0.id == track.id }) {
                                    editingTagsTrackIndex = idx
                                }
                            },
                            onEditCues: {
                                if let idx = model.tracks.firstIndex(where: { $0.id == track.id }) {
                                    editingCuesTrackIndex = idx
                                }
                            },
                            onRetry: {
                                if let idx = model.tracks.firstIndex(where: { $0.id == track.id }) {
                                    Task { @MainActor in
                                        await model.retryTrack(at: idx)
                                    }
                                }
                            },
                            onSkip: {
                                if let idx = model.tracks.firstIndex(where: { $0.id == track.id }) {
                                    model.removeTrack(at: idx)
                                }
                            }
                        )
                    }
                }
            }

            if model.isAnalyzing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("ANALYZING...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }
                .padding(10)
            }

            if let selected = model.selectedTrack {
                selectedTrackDetailPanel(selected: selected)
            }
        }
    }

    private func selectedTrackDetailPanel(selected: TrackAnalysis) -> some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("SELECTED TRACK")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
                Spacer()
                Button(action: { model.clearSelection() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(themeManager.surfaceColor.opacity(0.8))

            // Track detail view
            TrackDetailView(track: selected)
        }
    }

    private var dropZoneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60, weight: .thin))
                .foregroundColor(themeManager.tertiaryTextColor)

            Text("DROP AUDIO FILES")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.secondaryTextColor)

            Text("SUPPORTS MULTIPLE FILES • CSV EXPORT • HARMONIC MIXING")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeManager.tertiaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(
                    isDragOver ? themeManager.accentColor : themeManager.borderColor,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                .padding(40)
        )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let supportedExtensions = ["mp3", "wav", "m4a", "flac", "aiff", "aif"]
        var urls: [URL] = []

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                let fileExtension = url.pathExtension.lowercased()
                if supportedExtensions.contains(fileExtension) {
                    urls.append(url)
                }

                if provider == providers.last {
                    Task { @MainActor in
                        await model.addFiles(urls)
                    }
                }
            }
        }

        return true
    }

    private func setupNotificationObservers() {
        // Cmd+O - Open Files
        NotificationCenter.default.addObserver(
            forName: .openFiles,
            object: nil,
            queue: .main
        ) { _ in
            openFilePicker()
        }

        // Cmd+E - Export
        NotificationCenter.default.addObserver(
            forName: .exportTracks,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if !model.tracks.isEmpty {
                    if let url = model.exportToCSV() {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
            }
        }

        // Cmd+F - Focus Search
        NotificationCenter.default.addObserver(
            forName: .focusSearch,
            object: nil,
            queue: .main
        ) { _ in
            isSearchFocused = true
        }

        // Cmd+? - Show Help
        NotificationCenter.default.addObserver(
            forName: .showHelp,
            object: nil,
            queue: .main
        ) { _ in
            showHelp = true
        }

        // Cmd+Shift+L - Show Analysis Log
        NotificationCenter.default.addObserver(
            forName: .showAnalysisLog,
            object: nil,
            queue: .main
        ) { _ in
            showAnalysisLog = true
        }

        // Export to Rekordbox
        NotificationCenter.default.addObserver(
            forName: .exportRekordbox,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if !model.tracks.isEmpty {
                    if let url = model.exportToRekordbox() {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
            }
        }

        // Export to Serato
        NotificationCenter.default.addObserver(
            forName: .exportSerato,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if !model.tracks.isEmpty {
                    if let url = model.exportToSerato() {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
            }
        }

        // Export to Traktor
        NotificationCenter.default.addObserver(
            forName: .exportTraktor,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if !model.tracks.isEmpty {
                    if let url = model.exportToTraktor() {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
            }
        }

        // Export to Engine DJ
        NotificationCenter.default.addObserver(
            forName: .exportEngineDJ,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if !model.tracks.isEmpty {
                    if let url = model.exportToEngineDJ() {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
            }
        }

        // Export to Virtual DJ
        NotificationCenter.default.addObserver(
            forName: .exportVirtualDJ,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if !model.tracks.isEmpty {
                    if let url = model.exportToVirtualDJ() {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
            }
        }

        // Export to iTunes
        NotificationCenter.default.addObserver(
            forName: .exportiTunes,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if !model.tracks.isEmpty {
                    if let url = model.exportToiTunes() {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
            }
        }

        // Write Tags to Files
        NotificationCenter.default.addObserver(
            forName: .writeTags,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            guard let model = model else { return }
            Task { @MainActor in
                if let url = model.writeTagsToFiles() {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                }
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .audio,
            .mp3,
            .wav,
            .aiff
        ]
        panel.message = "Select audio files to analyze"

        if panel.runModal() == .OK {
            Task {
                await model.addFiles(panel.urls)
            }
        }
    }

    private var camelotWheelOverlay: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CAMELOT WHEEL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.textColor)
                Spacer()
                Button(action: { showCamelotWheel = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()
                .background(themeManager.borderColor)

            CamelotWheelView(tracks: model.tracks, selectedTrack: $model.selectedTrack)
                .frame(width: 280, height: 280)
                .padding(20)
        }
        .frame(width: 320)
        .background(themeManager.backgroundColor.opacity(0.95))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(themeManager.borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

struct EditSheetIdentifier: Identifiable {
    let index: Int
    var id: Int { index }
}

struct EnhancedTrackRow: View {
    let track: TrackAnalysis
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onAlbumArtUpdate: (NSImage) -> Void
    let onEditTags: () -> Void
    let onEditCues: () -> Void
    var onRetry: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showKeyChanges = false
    @State private var showAudioPreview = false
    @State private var showWaveformDetail = false
    @State private var isAlbumArtHovered = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow

            // Key change timeline (expandable)
            if showKeyChanges && !track.keyChanges.isEmpty {
                KeyChangeTimelineView(
                    keyChanges: track.keyChanges,
                    duration: track.duration
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Audio preview player (expandable)
            if showAudioPreview {
                AudioPreviewPlayer(track: track)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Expanded waveform with beatgrid (expandable)
            if showWaveformDetail {
                ExpandedWaveformView(track: track)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 12) {
            // Album art (droppable)
            albumArtView

            // Track name
            Button(action: onSelect) {
                Text(track.shortFileName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(track.isCompatible ? themeManager.accentColor : themeManager.textColor)
                    .frame(width: 160, alignment: .leading)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            // Key
            if track.isAnalyzing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 35)
                    .tint(themeManager.accentColor)
            } else if track.hasError {
                // Show error state with retry option
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text("ERROR")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.red)
                }
                .frame(width: 35)
                .help(track.error ?? track.errorType.displayDescription)
                .onTapGesture {
                    // This will be handled via the parent
                }
            } else {
                Text(track.key ?? "--")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(track.isCompatible ? themeManager.accentColor : themeManager.textColor)
                    .frame(width: 35)
            }

            // Camelot
            Text(track.camelotNotation ?? "--")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(track.isCompatible ? themeManager.accentColor : themeManager.textColor)
                .frame(width: 50)

            // BPM with decimal sublayer
            VStack(spacing: -2) {
                if let bpmString = track.bpm {
                    let components = bpmString.split(separator: ".")
                    if components.count == 2 {
                        Text(String(components[0]))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.textColor)
                        Text("." + String(components[1]))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(themeManager.secondaryTextColor)
                    } else {
                        Text(bpmString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.textColor)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                }
            }
            .frame(width: 50)

            // Duration
            let mins = Int(track.duration) / 60
            let secs = Int(track.duration) % 60
            Text(String(format: "%d:%02d", mins, secs))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeManager.secondaryTextColor)
                .frame(width: 45)

            // Waveform placeholder
            MiniWaveformView(filePath: track.filePath, beatGrid: track.beatGrid)
                .frame(width: 100, height: 30)
                .background(themeManager.surfaceColor.opacity(0.3))
                .cornerRadius(2)

            Spacer()

            // Error actions - show retry/skip buttons for failed tracks
            if track.hasError {
                HStack(spacing: 4) {
                    Text(track.errorType.displayTitle)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red.opacity(0.2))
                        )
                        .help(track.error ?? track.errorType.displayDescription)

                    if let onRetry = onRetry {
                        Button(action: onRetry) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Retry analysis")
                    }

                    if let onSkip = onSkip {
                        Button(action: onSkip) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 10))
                                .foregroundColor(themeManager.tertiaryTextColor)
                        }
                        .buttonStyle(.plain)
                        .help("Skip this track")
                    }
                }
            }

            // Tags button
            Button(action: onEditTags) {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 10))
                    if !track.tags.isEmpty {
                        Text("\(track.tags.count)")
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .foregroundColor(!track.tags.isEmpty ? themeManager.accentColor : themeManager.tertiaryTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(!track.tags.isEmpty ? themeManager.accentColorSubtle : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help("Edit tags and metadata")

            // Cue points button
            Button(action: onEditCues) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                    if !track.cuePoints.isEmpty {
                        Text("\(track.cuePoints.count)")
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .foregroundColor(!track.cuePoints.isEmpty ? themeManager.accentColor : themeManager.tertiaryTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(!track.cuePoints.isEmpty ? themeManager.accentColorSubtle : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help("Add cue points")

            // Audio preview button
            Button(action: { withAnimation { showAudioPreview.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: showAudioPreview ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.system(size: 10))
                    Text("preview")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(showAudioPreview ? themeManager.textColor : themeManager.tertiaryTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(showAudioPreview ? themeManager.surfaceColor.opacity(1.5) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help("Play track with waveform visualization")

            // Waveform detail button with beatgrid
            Button(action: { withAnimation { showWaveformDetail.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: showWaveformDetail ? "waveform.path.ecg" : "waveform.path")
                        .font(.system(size: 10))
                    Text("waveform")
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundColor(showWaveformDetail ? themeManager.textColor : themeManager.tertiaryTextColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(showWaveformDetail ? themeManager.surfaceColor.opacity(1.5) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help("View detailed waveform with beatgrid overlay")

            // Key changes indicator
            if !track.keyChanges.isEmpty {
                Button(action: { withAnimation { showKeyChanges.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 10))
                        Text("\(track.keyChanges.count) key change\(track.keyChanges.count == 1 ? "" : "s")")
                            .font(.system(size: 9, design: .monospaced))
                        Image(systemName: showKeyChanges ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(showKeyChanges ? themeManager.textColor : themeManager.tertiaryTextColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(showKeyChanges ? themeManager.surfaceColor.opacity(1.5) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("View timeline showing when keys change")
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(track.isCompatible ? themeManager.accentColorSubtle : (isSelected ? themeManager.surfaceColor.opacity(1) : themeManager.surfaceColor.opacity(0.4)))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                NSWorkspace.shared.selectFile(track.filePath.path, inFileViewerRootedAtPath: track.filePath.deletingLastPathComponent().path)
            }) {
                Text("Show in Finder")
                Image(systemName: "folder")
            }
        }
    }

    private var albumArtView: some View {
        Group {
            if let albumArt = track.albumArt {
                Image(nsImage: albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(themeManager.surfaceColor.opacity(2))
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }
                .frame(width: 50, height: 50)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isAlbumArtHovered ? themeManager.accentColor : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $isAlbumArtHovered) { providers in
            handleAlbumArtDrop(providers: providers)
        }
    }

    private func handleAlbumArtDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try loading as file URL first
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let image = NSImage(contentsOf: url) else {
                    return
                }
                DispatchQueue.main.async {
                    onAlbumArtUpdate(image)
                }
            }
            return true
        }

        // Try loading as image data
        if provider.hasItemConformingToTypeIdentifier("public.image") {
            provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                guard let data = data,
                      let image = NSImage(data: data) else {
                    return
                }
                DispatchQueue.main.async {
                    onAlbumArtUpdate(image)
                }
            }
            return true
        }

        return false
    }

    private func confidenceColor(_ confidence: Double?) -> Color {
        guard let conf = confidence else { return .gray }
        if conf > 0.8 { return .green }
        if conf > 0.6 { return .yellow }
        return .red
    }

    private func energyIcon(_ energy: String) -> String {
        switch energy {
        case "Very High": return "[VV]"
        case "High": return "[V]"
        case "Medium": return "[M]"
        case "Low": return "[L]"
        default: return "--"
        }
    }

    private func energyColor(_ energy: String) -> Color {
        switch energy {
        case "Very High": return .red
        case "High": return .orange
        case "Medium": return .yellow
        case "Low": return themeManager.tertiaryTextColor
        default: return themeManager.tertiaryTextColor
        }
    }
}

/// ExpandedWaveformView - Shows detailed waveform with beatgrid overlay
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
