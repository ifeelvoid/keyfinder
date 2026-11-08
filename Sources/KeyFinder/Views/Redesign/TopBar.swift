import SwiftUI

enum AppMode: String, CaseIterable {
    case files = "file", live = "live", mix = "mix"

    var title: String {
        switch self {
        case .files: return "FILES"
        case .live: return "LIVE"
        case .mix: return "MIX"
        }
    }
}

/// Logo, FILES / LIVE / MIX switcher, then the controls for the current mode.
struct TopBar: View {
    @Binding var mode: AppMode
    @ObservedObject var model: AudioAnalysisModel
    @ObservedObject var capture: LiveAudioCapture
    var searchFocus: FocusState<Bool>.Binding
    let onAddFiles: () -> Void
    let onShowLog: () -> Void
    let onShowHelp: () -> Void
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        HStack(spacing: 14) {
            KFLogo()
                .padding(.trailing, 6)
            modeSwitcher

            switch mode {
            case .files:
                searchField
                exportMenu
                Button(action: onAddFiles) { Label("ADD FILES", systemImage: "plus") }
                    .buttonStyle(KFButtonStyle(kind: .primary))
                    .help("Add audio files or a folder (⌘O)")
            case .live:
                Spacer()
                InputDevicePicker(capture: capture)
            case .mix:
                Spacer()
                exportMenu
            }
            moreMenu
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(Rectangle().fill(theme.textColor.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.allCases, id: \.self) { item in
                Button(action: { mode = item }) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .kerning(1.6)
                        .foregroundColor(mode == item ? theme.textColor : theme.tertiaryTextColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(mode == item ? theme.textColor.opacity(0.08) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.textColor.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.textColor.opacity(0.09), lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(theme.tertiaryTextColor)
            TextField("Search tracks, keys (4A), BPM (140-175)", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.textColor)
                .focused(searchFocus)
            if !model.searchText.isEmpty {
                Button(action: { model.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(theme.tertiaryTextColor)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.textColor.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.textColor.opacity(0.09), lineWidth: 1))
    }

    private var exportMenu: some View {
        Menu {
            ExportMenuItems(model: model)
        } label: {
            Label("EXPORT", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(KFButtonStyle())
        .modifier(OutlinedMenuLabel())
        .disabled(model.tracks.isEmpty)
    }

    /// Everything the old header exposed that the mockup has no room for.
    private var moreMenu: some View {
        Menu {
            Picker("Theme", selection: $theme.currentTheme) {
                ForEach(ThemeManager.Theme.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            Divider()
            if model.failedTracksCount > 0 {
                Button("Retry Failed (\(model.failedTracksCount))") {
                    Task { @MainActor in await model.retryFailedTracks() }
                }
                .disabled(model.isAnalyzing)
                Button("Skip Failed (\(model.failedTracksCount))") { model.skipFailedTracks() }
                Divider()
            }
            Button("Analysis Log", action: onShowLog)
            Button("Help", action: onShowHelp)
            Divider()
            Button("Clear Library", role: .destructive) { model.clearAll() }
                .disabled(model.tracks.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.secondaryTextColor)
                .frame(width: 34, height: 34)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Theme, log, failed tracks and more")
    }
}

/// Borderless menus ignore ButtonStyle, so draw the outline around the label instead.
private struct OutlinedMenuLabel: ViewModifier {
    @EnvironmentObject var theme: ThemeManager

    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.textColor.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.textColor.opacity(0.14), lineWidth: 1))
    }
}

/// All export formats; each reveals the written file in Finder.
struct ExportMenuItems: View {
    @ObservedObject var model: AudioAnalysisModel

    var body: some View {
        Group {
            item("CSV", "tablecells") { model.exportToCSV() }
            item("Rekordbox XML", "music.note.list") { model.exportToRekordbox() }
            item("Serato reference CSV", "waveform") { model.exportToSerato() }
            item("Traktor NML (experimental)", "square.and.arrow.up") { model.exportToTraktor() }
            item("Engine DJ", "doc.badge.arrow.up") { model.exportToEngineDJ() }
            item("Virtual DJ", "antenna.radiowaves.left.and.right") { model.exportToVirtualDJ() }
            item("iTunes XML", "music.note.list") { model.exportToiTunes() }
            Divider()
            item("Metadata Plan (CSV)", "tag") { model.exportMetadataPlan() }
        }
    }

    private func item(_ title: String, _ icon: String, _ export: @escaping () -> URL?) -> some View {
        Button(action: {
            if let url = export() {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            }
        }) {
            Label(title, systemImage: icon)
        }
    }
}
