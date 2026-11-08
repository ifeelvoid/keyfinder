import SwiftUI
import KeyFinderEngine

struct TagEditorView: View {
    @Binding var track: TrackAnalysis
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var newTag = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EDIT TAGS")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                    Text(track.fileName)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeManager.tertiaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(themeManager.tertiaryTextColor)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()
                .background(themeManager.borderColor)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Metadata Fields
                    VStack(alignment: .leading, spacing: 16) {
                        Text("METADATA")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)

                        MetadataField(label: "Artist", value: $track.artist)
                        MetadataField(label: "Title", value: $track.title)
                        MetadataField(label: "Genre", value: $track.genre)
                        MetadataField(label: "Year", value: $track.year)
                        MetadataField(label: "Comment", value: $track.comment, isMultiline: true)
                    }

                    Divider()
                        .background(themeManager.borderColor)

                    // Read-only detected info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ANALYSIS / CORRECTIONS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)

                        InfoRow(label: "Key", value: track.key ?? "Unknown")
                        Picker("Correct key", selection: Binding(
                            get: { track.key ?? "" },
                            set: { name in
                                guard let key = KeyDetector.MusicalKey.allCases.first(where: { $0.shortName == name }) else { return }
                                track.key = key.shortName
                                track.camelotNotation = key.camelotNotation
                            }
                        )) {
                            Text("Unknown").tag("")
                            ForEach(KeyDetector.MusicalKey.allCases, id: \.self) { key in
                                Text("\(key.rawValue) · \(key.camelotNotation)").tag(key.shortName)
                            }
                        }
                        Text("Detected: \(track.detectedKey ?? track.key ?? "Unknown"). Confidence is an algorithm score, not measured accuracy.")
                            .font(.caption).foregroundColor(themeManager.secondaryTextColor)
                        Button("Restore detected key") {
                            track.key = track.detectedKey
                            track.camelotNotation = track.detectedCamelot
                        }.disabled(track.detectedKey == nil)
                        InfoRow(label: "Camelot", value: track.camelotNotation ?? "Unknown")
                        InfoRow(label: "BPM", value: track.bpm ?? "Unknown")
                        InfoRow(label: "Confidence", value: track.confidenceText)
                        InfoRow(label: "Duration", value: formatDuration(track.duration))
                    }

                    Divider()
                        .background(themeManager.borderColor)

                    // Tags
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CUSTOM TAGS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)

                        // Add tag field
                        HStack(spacing: 8) {
                            TextField("Add tag (e.g., 'energetic', 'intro-track')", text: $newTag)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(themeManager.textColor)
                                .padding(8)
                                .background(themeManager.surfaceColor)
                                .cornerRadius(4)
                                .onSubmit {
                                    addTag()
                                }

                            Button(action: addTag) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(themeManager.accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newTag.isEmpty)
                        }

                        // Tag chips
                        if !track.tags.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(track.tags, id: \.self) { tag in
                                    TagChip(
                                        text: tag,
                                        onRemove: {
                                            track.tags.removeAll { $0 == tag }
                                        }
                                    )
                                }
                            }
                            .padding(.top, 4)
                        } else {
                            Text("No tags added")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(themeManager.tertiaryTextColor)
                                .padding(.vertical, 8)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }

            // Footer
            Divider()
                .background(themeManager.borderColor)

            HStack {
                Text("Saved in your KeyFinder crate • Audio files are unchanged")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
                Spacer()
                Button(action: { dismiss() }) {
                    Text("DONE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(themeManager.accentColor.opacity(0.3))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .frame(width: 500, height: 600)
        .background(themeManager.backgroundColor)
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty && !track.tags.contains(trimmed) {
            track.tags.append(trimmed)
            newTag = ""
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct MetadataField: View {
    let label: String
    @Binding var value: String?
    var isMultiline: Bool = false
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeManager.tertiaryTextColor)

            if isMultiline {
                TextEditor(text: Binding(
                    get: { value ?? "" },
                    set: { value = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeManager.textColor)
                .background(themeManager.surfaceColor)
                .cornerRadius(4)
                .frame(height: 60)
            } else {
                TextField("Not set", text: Binding(
                    get: { value ?? "" },
                    set: { value = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeManager.textColor)
                .padding(8)
                .background(themeManager.surfaceColor)
                .cornerRadius(4)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeManager.tertiaryTextColor)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.textColor)
        }
    }
}

struct TagChip: View {
    let text: String
    let onRemove: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeManager.textColor)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(themeManager.accentColor.opacity(0.3))
        .cornerRadius(12)
    }
}
