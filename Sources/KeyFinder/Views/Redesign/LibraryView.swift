import SwiftUI

/// FILES screen left column: "Library" heading, the track table and the drop zone.
struct LibraryView: View {
    @ObservedObject var model: AudioAnalysisModel
    let isDragOver: Bool
    let onAddFiles: () -> Void
    let onEditTags: (Int) -> Void
    let onEditCues: (Int) -> Void
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heading
                if let warning = model.libraryWarning {
                    Text(warning).font(.system(size: 11)).foregroundColor(.orange)
                }
                if !model.tracks.isEmpty { table }
                dropZone
            }
            .padding(24)
        }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Library")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(theme.textColor)
            Spacer()
            KF.label(summary, size: 9)
                .foregroundColor(theme.tertiaryTextColor)
        }
    }

    private var summary: String {
        let shown = model.filteredTracks.count
        let total = model.tracks.count
        let count = shown == total ? "\(total) track\(total == 1 ? "" : "s")" : "\(shown) of \(total) tracks"
        if model.isAnalyzing { return "\(count) · analyzing…" }
        return "\(count) · analyzed on this Mac"
    }

    private var table: some View {
        VStack(spacing: 0) {
            // Same widths as LibraryRow so the header lines up at any window size.
            HStack(spacing: 12) {
                Color.clear.frame(width: 36, height: 1)
                KF.label("Track", size: 9).frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                KF.label("Key", size: 9).frame(width: 104, alignment: .leading)
                KF.label("BPM", size: 9).frame(width: 64, alignment: .leading)
                KF.label("Time", size: 9).frame(width: 44, alignment: .leading)
                KF.label("Waveform", size: 9).frame(minWidth: 60, maxWidth: 230, alignment: .leading)
                Color.clear.frame(width: 24, height: 1)
            }
            .foregroundColor(theme.tertiaryTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if model.filteredTracks.isEmpty {
                Text("No tracks match “\(model.searchText)”")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme.tertiaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
            ForEach(model.filteredTracks) { track in
                Rectangle().fill(theme.textColor.opacity(0.06)).frame(height: 1)
                LibraryRow(
                    track: track,
                    isSelected: model.selectedTrack?.id == track.id,
                    onSelect: { model.selectTrackForHarmonicMixing(track) },
                    onRemove: { index(of: track).map(model.removeTrack(at:)) },
                    onRetry: {
                        if let i = index(of: track) { Task { @MainActor in await model.retryTrack(at: i) } }
                    },
                    onEditTags: { index(of: track).map(onEditTags) },
                    onEditCues: { index(of: track).map(onEditCues) },
                    onAlbumArt: { image in index(of: track).map { model.updateAlbumArt(at: $0, image: image) } }
                )
            }
        }
        .kfCard()
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func index(of track: TrackAnalysis) -> Int? {
        model.tracks.firstIndex { $0.id == track.id }
    }

    private var dropZone: some View {
        Button(action: onAddFiles) {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 14))
                Text("Drop audio files or a whole folder to analyze key and tempo")
                    .font(.system(size: 12))
            }
            .foregroundColor(isDragOver ? theme.accentColor : theme.secondaryTextColor)
            .frame(maxWidth: .infinity)
            .frame(height: model.tracks.isEmpty ? 220 : 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kfCard(dashed: true, highlighted: isDragOver)
        .help("Click to choose files or a folder")
    }
}

struct LibraryRow: View {
    let track: TrackAnalysis
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void
    let onEditTags: () -> Void
    let onEditCues: () -> Void
    let onAlbumArt: (NSImage) -> Void
    @EnvironmentObject var theme: ThemeManager
    @State private var showPreview = false
    @State private var showWaveform = false
    @State private var showKeyChanges = false
    @State private var isHovered = false
    @State private var isArtTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                tile
                titleColumn.frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                keyColumn.frame(width: 104, alignment: .leading)
                bpmColumn.frame(width: 64, alignment: .leading)
                Text(duration)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor)
                    .frame(width: 44, alignment: .leading)
                MiniWaveformView(filePath: track.filePath, beatGrid: nil,
                                 tint: isSelected ? theme.accentColor : theme.textColor.opacity(0.28))
                    .frame(minWidth: 60, maxWidth: 230)
                    .frame(height: 30)
                rowMenu
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? theme.accentColor.opacity(0.07) : isHovered ? theme.textColor.opacity(0.025) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .onHover { isHovered = $0 }

            if showKeyChanges && !track.keyChanges.isEmpty {
                KeyChangeTimelineView(keyChanges: track.keyChanges, duration: track.duration)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            if showPreview {
                AudioPreviewPlayer(track: track).padding(.horizontal, 20).padding(.vertical, 8)
            }
            if showWaveform {
                ExpandedWaveformView(track: track).padding(.horizontal, 20).padding(.vertical, 8)
            }
        }
    }

    private var tile: some View {
        Group {
            if let art = track.albumArt {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                Text(KF.initials(track.title ?? displayTitle))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.textColor.opacity(0.05))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(isArtTargeted ? theme.accentColor : theme.textColor.opacity(0.1), lineWidth: 1))
        .onDrop(of: [.fileURL, .image], isTargeted: $isArtTargeted, perform: loadArt)
        .help("Drop an image here to set artwork")
    }

    private var displayTitle: String {
        track.title ?? (track.fileName as NSString).deletingPathExtension
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected || track.isCompatible ? theme.accentColor : theme.textColor)
                .lineLimit(1)
            Text(track.fileName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.tertiaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder private var keyColumn: some View {
        if track.isAnalyzing {
            ProgressView().scaleEffect(0.55).frame(height: 20)
        } else if track.hasError {
            Text("ERROR")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.red)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.14)))
                .help(track.error ?? track.errorType.displayDescription)
        } else {
            KeyPill(key: track.key, camelot: track.camelotNotation)
        }
    }

    private var bpmColumn: some View {
        KF.splitNumber(track.bpm ?? "--", size: 13, theme: theme)
    }

    private var duration: String {
        track.duration > 0 ? String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60) : "--"
    }

    private var rowMenu: some View {
        Menu {
            Toggle("Preview", isOn: animated($showPreview))
            Toggle("Waveform & Beat Grid", isOn: animated($showWaveform))
            if !track.keyChanges.isEmpty {
                Toggle("Key Changes (\(track.keyChanges.count))", isOn: animated($showKeyChanges))
            }
            Divider()
            Button("Tags & Metadata…", action: onEditTags)
            Button("Cue Points…", action: onEditCues)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([track.filePath]) }
            if track.hasError {
                Divider()
                Button("Retry Analysis", action: onRetry)
            }
            Divider()
            Button("Remove from Library", role: .destructive, action: onRemove)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isHovered || isSelected ? theme.secondaryTextColor : theme.tertiaryTextColor)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Preview, tags, cues and more")
    }

    private func animated(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue }, set: { value in withAnimation { binding.wrappedValue = value } })
    }

    private func loadArt(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil),
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async { onAlbumArt(image) }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier("public.image") {
            provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { onAlbumArt(image) }
            }
            return true
        }
        return false
    }
}
