import SwiftUI
import KeyFinderEngine

/// FILES screen right column for the selected track.
struct NowSelectedPanel: View {
    @ObservedObject var model: AudioAnalysisModel
    @EnvironmentObject var theme: ThemeManager
    @State private var showPlayer = false

    /// The model's selection is a snapshot; read the live entry so re-analysis shows up.
    private var track: TrackAnalysis? {
        guard let id = model.selectedTrack?.id else { return nil }
        return model.tracks.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            if let track {
                VStack(alignment: .leading, spacing: 18) {
                    header(track)
                    if showPlayer { AudioPreviewPlayer(track: track) }
                    HStack(spacing: 10) {
                        keyCard(track)
                        tempoCard(track)
                    }
                    MiniWaveformView(filePath: track.filePath, beatGrid: nil, tint: theme.accentColor)
                        .id(track.id)
                        .frame(height: 40)
                    wheel(track)
                    mixes(track)
                }
                .padding(20)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 28, weight: .light))
                    Text("Select a track to see its key, tempo and harmonic matches")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(theme.tertiaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
                .padding(.horizontal, 24)
            }
        }
        .frame(width: 300)
        .background(theme.textColor.opacity(0.018))
        .overlay(Rectangle().fill(theme.textColor.opacity(0.08)).frame(width: 1), alignment: .leading)
        .onChange(of: model.selectedTrack?.id) { _ in showPlayer = false }
    }

    private func header(_ track: TrackAnalysis) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                KF.label("Now selected", size: 9).foregroundColor(theme.tertiaryTextColor)
                Text(title(track))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.textColor)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: { withAnimation { showPlayer.toggle() } }) {
                Image(systemName: showPlayer ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textColor)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(theme.textColor.opacity(0.2), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(showPlayer ? "Hide player" : "Preview this track")
        }
    }

    private func keyCard(_ track: TrackAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            KF.label("Key", size: 9).foregroundColor(theme.tertiaryTextColor)
            HStack(alignment: .center, spacing: 8) {
                Text(KF.display(track.key))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(theme.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let camelot = track.camelotNotation {
                    KeyPill(key: nil, camelot: camelot)
                }
            }
            Text(Self.fullKeyName(track.key))
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kfCard(padding: 12)
    }

    private func tempoCard(_ track: TrackAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            KF.label("Tempo", size: 9).foregroundColor(theme.tertiaryTextColor)
            KF.splitNumber(track.bpm ?? "--", size: 34, theme: theme)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(tempoNote(track))
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kfCard(padding: 12)
    }

    /// Shows the other way a DJ might count the same groove.
    private func tempoNote(_ track: TrackAnalysis) -> String {
        let time = track.duration > 0 ? String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60) : ""
        guard let bpm = Double(track.bpm ?? ""), bpm > 0 else { return time }
        let alternate = bpm >= 120 ? String(format: "Half-time %.1f", bpm / 2) : String(format: "Double-time %.1f", bpm * 2)
        return time.isEmpty ? alternate : "\(alternate) · \(time)"
    }

    private func wheel(_ track: TrackAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                KF.label("Camelot", size: 9).foregroundColor(theme.tertiaryTextColor)
                Spacer()
                Text("Lit = harmonic moves")
                    .font(.system(size: 10))
                    .foregroundColor(theme.tertiaryTextColor)
            }
            CamelotWheelView(selected: track.camelotNotation,
                             compatible: Self.harmonicMoves(from: track.camelotNotation),
                             counts: Dictionary(grouping: model.tracks.compactMap(\.camelotNotation), by: { $0 })
                                .mapValues(\.count),
                             centerKey: track.key)
                .frame(height: 260)
        }
    }

    private func mixes(_ track: TrackAnalysis) -> some View {
        let matches = model.tracks
            .filter { $0.id != track.id }
            .compactMap { other in model.transition(from: track, to: other).map { (other, $0) } }
            .sorted { $0.1.score > $1.1.score }
            .prefix(8)
        return VStack(alignment: .leading, spacing: 8) {
            KF.label("Mixes with in your library", size: 9).foregroundColor(theme.tertiaryTextColor)
            if matches.isEmpty {
                Text("No compatible key within ±8% tempo yet")
                    .font(.system(size: 11))
                    .foregroundColor(theme.tertiaryTextColor)
                    .padding(.vertical, 6)
            }
            ForEach(Array(matches), id: \.0.id) { other, assessment in
                Button(action: { model.selectTrackForHarmonicMixing(other) }) {
                    mixRow(other, assessment)
                }
                .buttonStyle(.plain)
                .help(assessment.reasons.joined(separator: " · "))
            }
        }
    }

    private func mixRow(_ other: TrackAnalysis, _ assessment: TransitionAssessment) -> some View {
        HStack(spacing: 10) {
            Circle().fill(KF.camelotColor(other.camelotNotation)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(other))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textColor)
                    .lineLimit(1)
                Text(assessment.reasons.first ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(theme.tertiaryTextColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(other.camelotNotation ?? "--")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textColor)
                Text(assessment.reasons.dropFirst().first.map(Self.tempoLabel) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.tertiaryTextColor)
            }
        }
        .padding(10)
        .contentShape(Rectangle())
        .kfCard()
    }

    private func title(_ track: TrackAnalysis) -> String {
        track.title ?? (track.fileName as NSString).deletingPathExtension
    }

    /// "Tempo +2.1%" → "+2.1% BPM".
    static func tempoLabel(_ reason: String) -> String {
        reason.replacingOccurrences(of: "Tempo ", with: "") + " BPM"
    }

    /// "Fm" → "F minor", "A#" → "A# major".
    static func fullKeyName(_ key: String?) -> String {
        guard let key, !key.isEmpty, key != "--" else { return "" }
        return key.hasSuffix("m") ? "\(key.dropLast()) minor" : "\(key) major"
    }

    /// Same key, relative major/minor and one step either way: the moves MixRanker accepts.
    static func harmonicMoves(from camelot: String?) -> Set<String> {
        guard let camelot, let mode = camelot.last, let number = Int(camelot.dropLast()) else { return [] }
        let previous = number == 1 ? 12 : number - 1
        let next = number == 12 ? 1 : number + 1
        return ["\(previous)\(mode)", "\(next)\(mode)", "\(number)\(mode == "A" ? "B" : "A")"]
    }
}
