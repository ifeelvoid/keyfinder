import SwiftUI

struct CuePointsView: View {
    @Binding var track: TrackAnalysis
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var newCueName = ""
    @State private var selectedColor = "purple"

    let availableColors = [
        ("purple", Color(red: 0.7, green: 0.5, blue: 1.0)),
        ("red", Color.red),
        ("orange", Color.orange),
        ("yellow", Color.yellow),
        ("green", Color.green),
        ("blue", Color.blue),
        ("pink", Color.pink)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CUE POINTS")
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
                    // Instructions
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.accentColor)
                        Text("Audition suggested cues and approve them before export. Add manual cues at the playback position.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                    .padding(12)
                    .background(themeManager.accentColorSubtle)
                    .cornerRadius(6)

                    // Waveform with cue markers
                    waveformView

                    // Playback controls
                    HStack(spacing: 12) {
                        Button(action: { playerManager.togglePlayPause() }) {
                            Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(themeManager.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button(action: { playerManager.stop() }) {
                            Image(systemName: "stop.circle")
                                .font(.system(size: 28))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(formatTime(playerManager.currentTime)) / \(formatTime(playerManager.duration))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.textColor)
                    }

                    Divider()
                        .background(themeManager.borderColor)

                    // Add cue point
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CREATE CUE POINT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)

                        HStack(spacing: 8) {
                            TextField("Cue name (e.g., 'Drop', 'Breakdown')", text: $newCueName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(themeManager.textColor)
                                .padding(8)
                                .background(themeManager.surfaceColor)
                                .cornerRadius(4)

                            // Color picker
                            Menu {
                                ForEach(availableColors, id: \.0) { colorName, color in
                                    Button(action: { selectedColor = colorName }) {
                                        HStack {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 12, height: 12)
                                            Text(colorName.capitalized)
                                            if selectedColor == colorName {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Circle()
                                    .fill(colorForName(selectedColor))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(themeManager.borderColor, lineWidth: 1)
                                    )
                            }

                            Button(action: addCuePoint) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("ADD CUE")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                }
                                .foregroundColor(themeManager.textColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(themeManager.accentColor.opacity(0.3))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .disabled(newCueName.isEmpty || track.cuePoints.count >= 8 || playerManager.duration <= 0)
                        }

                        Text("Current time: \(formatTime(playerManager.currentTime))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(themeManager.tertiaryTextColor)
                    }

                    Divider()
                        .background(themeManager.borderColor)

                    // Cue points list
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("CUE POINTS (\(track.cuePoints.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(themeManager.tertiaryTextColor)
                            Spacer()
                            if track.cuePoints.contains(where: { $0.isSuggested }) {
                                Button("Approve suggestions") {
                                    for index in track.cuePoints.indices { track.cuePoints[index].isSuggested = false }
                                }
                                .font(.caption)
                            }
                            if !track.cuePoints.isEmpty {
                                Button(action: { track.cuePoints.removeAll() }) {
                                    Text("Clear All")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(themeManager.tertiaryTextColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if track.cuePoints.isEmpty {
                            Text("No cue points created yet")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(themeManager.tertiaryTextColor)
                                .padding(.vertical, 12)
                        } else {
                            ForEach($track.cuePoints) { $cue in
                                HStack {
                                    TextField("Cue name", text: $cue.name)
                                    TextField("Seconds", value: $cue.timestamp, format: .number.precision(.fractionLength(2)))
                                        .frame(width: 80)
                                    if cue.isSuggested {
                                        Button("Approve") { cue.isSuggested = false }
                                    }
                                }
                                .font(.caption)
                            }
                            VStack(spacing: 8) {
                                ForEach(track.cuePoints.sorted(by: { $0.timestamp < $1.timestamp })) { cue in
                                    CuePointRow(
                                        cue: cue,
                                        onJump: {
                                            playerManager.seek(to: cue.timestamp)
                                        },
                                        onDelete: {
                                            track.cuePoints.removeAll { $0.id == cue.id }
                                        }
                                    )
                                }
                            }
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
                Text("Up to 8 cues • Approved cues export to Rekordbox XML")
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
        .frame(width: 600, height: 700)
        .background(themeManager.backgroundColor)
        .onAppear {
            playerManager.loadAudio(from: track.filePath)
        }
        .onDisappear {
            playerManager.stop()
            for index in track.cuePoints.indices {
                let time = track.cuePoints[index].timestamp
                track.cuePoints[index].timestamp = time.isFinite ? max(0, min(time, max(0, track.duration - 0.01))) : 0
            }
        }
    }

    private var waveformView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(themeManager.surfaceColor)
                    .frame(height: 80)
                    .cornerRadius(4)

                // Waveform bars
                HStack(spacing: 1) {
                    ForEach(Array(playerManager.waveformData.enumerated()), id: \.offset) { index, amplitude in
                        Rectangle()
                            .fill(waveformColor(for: index, geometry: geometry))
                            .frame(width: max(1, geometry.size.width / CGFloat(playerManager.waveformData.count) - 1))
                            .frame(height: max(2, CGFloat(amplitude) * 80))
                    }
                }
                .frame(height: 80, alignment: .center)

                // Cue point markers
                ForEach(track.cuePoints) { cue in
                    let position = max(0, min(cue.timestamp / max(playerManager.duration, 0.01), 1)) * geometry.size.width
                    Rectangle()
                        .fill(colorForName(cue.color))
                        .frame(width: 3)
                        .offset(x: position)
                }

                // Playhead
                if playerManager.duration > 0 {
                    Rectangle()
                        .fill(themeManager.textColor.opacity(0.9))
                        .frame(width: 2)
                        .offset(x: playheadPosition(in: geometry.size.width))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = max(0, min(value.location.x, geometry.size.width))
                        let time = (position / geometry.size.width) * playerManager.duration
                        playerManager.seek(to: time)
                    }
            )
        }
        .frame(height: 80)
    }

    private func waveformColor(for index: Int, geometry: GeometryProxy) -> Color {
        let position = CGFloat(index) / CGFloat(playerManager.waveformData.count)
        let currentPosition = playerManager.currentTime / playerManager.duration

        if position <= currentPosition {
            return themeManager.accentColor
        } else {
            return themeManager.tertiaryTextColor.opacity(0.3)
        }
    }

    private func playheadPosition(in width: CGFloat) -> CGFloat {
        guard playerManager.duration > 0 else { return 0 }
        return (playerManager.currentTime / playerManager.duration) * width
    }

    private func addCuePoint() {
        let trimmed = newCueName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let cue = CuePoint(
                timestamp: playerManager.currentTime,
                name: trimmed,
                color: selectedColor
            )
            track.cuePoints.append(cue)
            newCueName = ""
        }
    }

    private func colorForName(_ name: String) -> Color {
        availableColors.first(where: { $0.0 == name })?.1 ?? themeManager.accentColor
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct CuePointRow: View {
    let cue: CuePoint
    let onJump: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colorForName(cue.color))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(cue.name + (cue.isSuggested ? " · Suggested" : ""))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.textColor)
                Text(formatTime(cue.timestamp))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }

            Spacer()

            Button(action: onJump) {
                Image(systemName: "play.circle")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .help("Jump to cue point")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }
            .buttonStyle(.plain)
            .help("Delete cue point")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(themeManager.surfaceColor.opacity(0.5))
        .cornerRadius(4)
    }

    private func colorForName(_ name: String) -> Color {
        let colors: [String: Color] = [
            "purple": Color(red: 0.7, green: 0.5, blue: 1.0),
            "red": .red,
            "orange": .orange,
            "yellow": .yellow,
            "green": .green,
            "blue": .blue,
            "pink": .pink
        ]
        return colors[name] ?? Color(red: 0.7, green: 0.5, blue: 1.0)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
