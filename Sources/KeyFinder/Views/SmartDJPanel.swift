import SwiftUI
import KeyFinderEngine

/// Panel for Smart DJ features: harmonic mix generation and playlist management
struct SmartDJPanel: View {
    @ObservedObject var model: AudioAnalysisModel
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var maxTracks: Int = 20
    @State private var selectedStartKey: String? = nil
    /// Shown as the MIX tab rather than a sheet: no close button.
    var embedded = false

    private let camelotKeys = (1...12).flatMap { num in ["\(num)A", "\(num)B"] }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Mix")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                KF.label("Harmonic set from your library", size: 9)
                    .foregroundColor(themeManager.tertiaryTextColor)
                    .padding(.leading, 10)

                Spacer()

                if !embedded {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(themeManager.tertiaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Mix Settings
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MIX SETTINGS")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.tertiaryTextColor)

                            HStack {
                                Text("Max Tracks:")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(themeManager.secondaryTextColor)

                                Stepper(value: $maxTracks, in: 5...100, step: 5) {
                                    Text("\(maxTracks)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(themeManager.textColor)
                                        .frame(width: 40)
                                }
                            }

                            HStack {
                                Text("Start Key (optional):")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(themeManager.secondaryTextColor)

                                Picker("", selection: $selectedStartKey) {
                                    Text("First in crate").tag(nil as String?)
                                    ForEach(camelotKeys, id: \.self) { key in
                                        Text(key).tag(key as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                            }

                            Picker("Energy direction", selection: $model.mixDirection) {
                                ForEach(EnergyDirection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            Text("Only compatible keys within 8% tempo difference. Energy is an RMS estimate; audition transitions.")
                                .font(.caption).foregroundColor(themeManager.secondaryTextColor)
                            Button(action: {
                                model.generateHarmonicMix(maxTracks: maxTracks, startWithKey: selectedStartKey)
                            }) {
                                HStack {
                                    Image(systemName: "waveform.badge.plus")
                                    Text("GENERATE MIX")
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(themeManager.textOnAccentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(themeManager.accentColor)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                    }
                    .kfCard()

                    // Generated Mix Playlist
                    if !model.generatedMixPlaylist.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("GENERATED MIX PLAYLIST")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(themeManager.tertiaryTextColor)

                                    Spacer()

                                    Text("\(model.generatedMixPlaylist.count) tracks")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(themeManager.tertiaryTextColor)
                                }

                                // Export button
                                Button(action: {
                                    if let url = model.exportMixPlaylist() {
                                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Export Playlist")
                                    }
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(themeManager.secondaryTextColor)
                                }
                                .buttonStyle(.plain)

                                Divider()

                                // Track list
                                ForEach(Array(model.generatedMixPlaylist.enumerated()), id: \.element.id) { index, track in
                                    HStack(spacing: 12) {
                                        // Order number
                                        Text("\(index + 1)")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(themeManager.tertiaryTextColor)
                                            .frame(width: 24)

                                        // Track info
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.fileName)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(themeManager.textColor)
                                                .lineLimit(1)

                                            HStack(spacing: 8) {
                                                if let key = track.key {
                                                    Text(key)
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(themeManager.secondaryTextColor)
                                                }
                                                if let camelot = track.camelotNotation {
                                                    Text(camelot)
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(themeManager.accentColor)
                                                }
                                                if let bpm = track.bpm {
                                                    Text("\(bpm) BPM")
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .foregroundColor(themeManager.tertiaryTextColor)
                                                }
                                            }
                                            Text(model.mixReasons[track.id] ?? "")
                                                .font(.caption)
                                                .foregroundColor(themeManager.secondaryTextColor)
                                        }

                                        Spacer()

                                        // Compatibility indicator
                                        if index > 0 {
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding(.vertical, 6)

                                    if index < model.generatedMixPlaylist.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(12)
                        }
                        .kfCard()
                    }

                    // Info text
                    if model.generatedMixPlaylist.isEmpty {
                        Text("Click 'Generate Mix' to create a harmonically mixed playlist from your analyzed tracks. The algorithm will arrange tracks that are harmonically compatible for smooth transitions.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .kfCard(padding: 16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .background(themeManager.backgroundColor)
        .onExitCommand { dismiss() }
    }
}
