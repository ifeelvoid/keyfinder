import SwiftUI

struct HelpView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KEY FINDER")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.textColor)
                        Text("v1.4 - Professional Key & BPM Detection")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(themeManager.tertiaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                Divider()
                    .background(themeManager.borderColor)

                // Quick Start
                HelpSection(
                    title: "QUICK START",
                    icon: "bolt.fill"
                ) {
                    HelpItem(
                        number: "1",
                        title: "Add Audio Files",
                        description: "Drag & drop audio files or press Cmd+O"
                    )
                    HelpItem(
                        number: "2",
                        title: "Analyze",
                        description: "Key, BPM, and Camelot notation detected automatically"
                    )
                    HelpItem(
                        number: "3",
                        title: "Export",
                        description: "Export Rekordbox XML or a metadata reference CSV"
                    )
                }

                // Features
                HelpSection(
                    title: "FEATURES",
                    icon: "star.fill"
                ) {
                    FeatureItem(
                        icon: "music.note",
                        title: "Musical Key Detection",
                        description: "Advanced Krumhansl-Schmuckler algorithm with chord progression analysis"
                    )
                    FeatureItem(
                        icon: "metronome",
                        title: "BPM Detection",
                        description: "Accurate tempo detection for DJ mixing"
                    )
                    FeatureItem(
                        icon: "waveform.path",
                        title: "Key Change Timeline",
                        description: "Visual timeline showing where songs modulate to different keys"
                    )
                    FeatureItem(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Harmonic Mixing",
                        description: "Camelot Wheel notation with compatible track highlighting"
                    )
                    FeatureItem(
                        icon: "speaker.wave.3",
                        title: "Audio Preview",
                        description: "Play tracks with interactive waveform visualization"
                    )
                    FeatureItem(
                        icon: "photo",
                        title: "Album Art",
                        description: "Drag & drop images to replace or add album artwork"
                    )
                }

                // Track Controls
                HelpSection(
                    title: "TRACK CONTROLS",
                    icon: "slider.horizontal.3"
                ) {
                    ControlItem(
                        icon: "speaker.wave.2",
                        description: "Audio Preview - Click to play track with waveform"
                    )
                    ControlItem(
                        icon: "waveform.path",
                        description: "Key Changes - View timeline of detected key modulations"
                    )
                    ControlItem(
                        icon: "xmark.circle",
                        description: "Remove - Delete track from list"
                    )
                }

                // Keyboard Shortcuts
                HelpSection(
                    title: "KEYBOARD SHORTCUTS",
                    icon: "keyboard"
                ) {
                    ShortcutItem(shortcut: "Cmd + O", description: "Open audio files")
                    ShortcutItem(shortcut: "Cmd + E", description: "Export to CSV")
                    ShortcutItem(shortcut: "Cmd + F", description: "Focus search field")
                }

                // Understanding Results
                HelpSection(
                    title: "UNDERSTANDING RESULTS",
                    icon: "chart.bar.fill"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ResultExplanation(
                            title: "Key",
                            description: "Musical key in standard notation (e.g., C major, A minor)"
                        )
                        ResultExplanation(
                            title: "Camelot",
                            description: "DJ-friendly notation for harmonic mixing (1A-12A for minor, 1B-12B for major)"
                        )
                        ResultExplanation(
                            title: "BPM",
                            description: "Beats per minute - the track's tempo"
                        )
                        ResultExplanation(
                            title: "Confidence",
                            description: "Detection accuracy: Green (>75%), Yellow (50-75%), Red (<50%)"
                        )
                        ResultExplanation(
                            title: "Key Changes",
                            description: "Number of detected modulations - click to view timeline"
                        )
                    }
                }

                // Harmonic Mixing Guide
                HelpSection(
                    title: "HARMONIC MIXING",
                    icon: "music.note.list"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Click any track to highlight compatible mixes:")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(themeManager.textColor)

                        MixingRule(rule: "Same number", example: "8A → 8B")
                        MixingRule(rule: "±1 number", example: "8A → 7A or 9A")
                        MixingRule(rule: "Perfect Fifth", example: "8A → 3A (+7)")

                        Text("Compatible tracks are highlighted in green")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)
                            .padding(.top, 4)
                    }
                }

                // Export Formats
                HelpSection(
                    title: "EXPORT FORMATS",
                    icon: "square.and.arrow.up"
                ) {
                    ExportFormat(
                        format: "CSV",
                        description: "Universal format with all track data"
                    )
                    ExportFormat(
                        format: "Rekordbox XML",
                        description: "Import directly into Pioneer Rekordbox"
                    )
                    ExportFormat(
                        format: "Serato CSV",
                        description: "Reference CSV only; does not write Serato tags or cues"
                    )
                }

                // Tips
                HelpSection(
                    title: "PRO TIPS",
                    icon: "lightbulb.fill"
                ) {
                    TipItem(tip: "Right-click any track to reveal it in Finder")
                    TipItem(tip: "Use search to filter tracks by key, BPM, or filename")
                    TipItem(tip: "Drag images onto album art to replace artwork")
                    TipItem(tip: "Click waveform to seek to specific position")
                    TipItem(tip: "Switch theme via menu or header icon")
                }

                HelpSection(
                    title: "DATA CREDITS",
                    icon: "music.quarternote.3"
                ) {
                    TipItem(tip: "Key profiles and model weights derive from CC BY-SA 4.0 annotations: GiantSteps+ v2 (zenodo.org/records/4153506) and GiantSteps-MTG / Beatport EDM Key by Eduard Mas Marín and Ángel Faraldo (zenodo.org/records/1101082)")
                    TipItem(tip: "No Essentia or madmom code or models are included; accuracy notes are in ACCURACY.md")
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .frame(width: 600, height: 700)
        .background(themeManager.backgroundColor)
    }
}

struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.secondaryTextColor)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.textColor)
            }

            content
                .padding(.leading, 20)
        }
    }
}

struct HelpItem: View {
    let number: String
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(themeManager.secondaryTextColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.textColor)
                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeManager.secondaryTextColor)
            }
        }
    }
}

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.textColor)
                Text(description)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }
        }
    }
}

struct ControlItem: View {
    let icon: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(themeManager.secondaryTextColor)
                .frame(width: 20)

            Text(description)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeManager.textColor)
        }
    }
}

struct ShortcutItem: View {
    let shortcut: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.textColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(themeManager.surfaceColor)
                .cornerRadius(4)
                .frame(width: 100, alignment: .leading)

            Text(description)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeManager.secondaryTextColor)
        }
    }
}

struct ResultExplanation: View {
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(themeManager.textColor)
            Text(description)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeManager.secondaryTextColor)
        }
    }
}

struct MixingRule: View {
    let rule: String
    let example: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            Text("•")
                .foregroundColor(themeManager.tertiaryTextColor)
            Text(rule)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeManager.textColor)
            Text("→")
                .foregroundColor(themeManager.tertiaryTextColor)
            Text(example)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.secondaryTextColor)
        }
    }
}

struct ExportFormat: View {
    let format: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("•")
                .foregroundColor(themeManager.tertiaryTextColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(format)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.textColor)
                Text(description)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }
        }
    }
}

struct TipItem: View {
    let tip: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("→")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(themeManager.secondaryTextColor)
            Text(tip)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeManager.textColor)
        }
    }
}
