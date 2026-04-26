import SwiftUI

struct TrackDetailView: View {
    let track: TrackAnalysis
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 24) {
            // Album art - large
            albumArtView

            // Details
            VStack(alignment: .leading, spacing: 12) {
                // Key - large and prominent
                keyDisplay

                // Camelot
                HStack {
                    Text(track.camelotNotation ?? "--")
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                    Text("Camelot")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }

                // BPM
                HStack {
                    Text(track.bpm ?? "--")
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.textColor)
                    Text("BPM")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }

                // Duration
                HStack {
                    Text(formatDuration(track.duration))
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(themeManager.secondaryTextColor)
                    Text("Duration")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                // Waveform overview
                MiniWaveformView(track: track)
                    .frame(height: 60)
            }

            Spacer()
        }
        .padding(24)
        .background(Color.white.opacity(0.05))
    }

    private var albumArtView: some View {
        Group {
            if let art = track.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 180, height: 180)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }
        }
    }

    private var keyDisplay: some View {
        Group {
            if track.isAnalyzing {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(height: 48)
            } else if track.hasError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                    Text("ERROR")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                }
            } else {
                Text(track.key ?? "--")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
