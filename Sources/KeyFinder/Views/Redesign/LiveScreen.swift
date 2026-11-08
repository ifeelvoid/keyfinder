import SwiftUI

/// LIVE screen: large key read, Camelot, tempo, pitch energy and hold / reset / save.
struct LiveScreen: View {
    @ObservedObject var capture: LiveAudioCapture
    let onSave: (URL) -> Void
    @EnvironmentObject var theme: ThemeManager
    @State private var notice: String?

    private static let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 640
            VStack(spacing: compact ? 22 : 34) {
                Spacer(minLength: 0)
                status
                reading(compact: compact)
                pitchEnergy(height: compact ? 110 : 150)
                actions
                if let notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryTextColor)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var status: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(capture.isCapturing ? theme.accentColor : theme.tertiaryTextColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(theme.accentColor.opacity(capture.isCapturing ? 0.35 : 0), lineWidth: 4))
            if let message = capture.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            } else {
                KF.label(statusText, size: 11)
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
    }

    private var statusText: String {
        guard capture.isCapturing else { return "Not listening" }
        let seconds = String(format: "%.1fs captured", capture.capturedSeconds)
        if capture.isHeld { return "Result held · \(seconds)" }
        if capture.currentKey == "--" { return "Listening · \(seconds) · first read at 5s" }
        return "Listening · \(seconds)"
    }

    private func reading(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: compact ? 36 : 56) {
            VStack(alignment: .leading, spacing: 0) {
                KF.label("Key", size: 11).foregroundColor(theme.tertiaryTextColor)
                Text(KF.display(capture.currentKey))
                    .font(.system(size: compact ? 130 : 190, weight: .bold))
                    .foregroundColor(capture.currentKey == "--" ? theme.textColor.opacity(0.15)
                                     : theme.textColor.opacity(capture.isHeld ? 0.7 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel("Key \(NowSelectedPanel.fullKeyName(capture.currentKey))")
            }
            VStack(alignment: .leading, spacing: compact ? 14 : 22) {
                Text(KF.display(capture.currentCamelot))
                    .font(.system(size: compact ? 30 : 40, weight: .bold, design: .monospaced))
                    .foregroundColor(KF.camelotColor(capture.currentCamelot))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(KF.camelotColor(capture.currentCamelot).opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(KF.camelotColor(capture.currentCamelot).opacity(0.35), lineWidth: 1))
                VStack(alignment: .leading, spacing: 6) {
                    KF.label("Tempo", size: 11).foregroundColor(theme.tertiaryTextColor)
                    KF.splitNumber(capture.currentBPM, size: compact ? 34 : 44, theme: theme)
                }
            }
        }
    }

    private func pitchEnergy(height: CGFloat) -> some View {
        let energy = capture.pitchEnergy
        let strongest = Set(energy.enumerated().filter { $0.element > 0 }
            .sorted { $0.element > $1.element }.prefix(3).map(\.offset))
        return VStack(spacing: 10) {
            HStack {
                KF.label("Pitch energy", size: 10).foregroundColor(theme.tertiaryTextColor)
                Spacer()
                Text("Tallest bars shape the key read")
                    .font(.system(size: 11))
                    .foregroundColor(theme.tertiaryTextColor)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<12, id: \.self) { pitch in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(strongest.contains(pitch) ? theme.accentColor : theme.textColor.opacity(0.12))
                            .frame(height: max(4, height * CGFloat(energy[pitch])))
                            .frame(height: height, alignment: .bottom)
                        Text(Self.notes[pitch])
                            .font(.system(size: 11, weight: strongest.contains(pitch) ? .bold : .medium, design: .monospaced))
                            .foregroundColor(strongest.contains(pitch) ? theme.textColor : theme.tertiaryTextColor)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Self.notes[pitch]) \(Int(energy[pitch] * 100)) percent")
                }
            }
            .animation(.easeOut(duration: 0.4), value: energy)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(capture.isHeld ? "RELEASE" : "HOLD RESULT") { capture.isHeld.toggle() }
                .buttonStyle(KFButtonStyle(kind: .primary))
                .disabled(capture.currentKey == "--")
                .help("Freeze the current read while the track keeps playing")
            Button("RESET") {
                capture.reset()
                show("Started a fresh read")
            }
            .buttonStyle(KFButtonStyle())
            .help("Forget what was heard and start over")
            Button("SAVE TO LIBRARY", action: save)
                .buttonStyle(KFButtonStyle())
                .disabled(capture.capturedSeconds < LiveAnalysisWindow.stepSeconds)
                .help("Save the last \(Int(LiveAudioCapture.maxSavedSeconds)) seconds as a WAV (Music › KeyFinder Captures) and analyze it in FILES")
        }
    }

    private func save() {
        do {
            let url = try capture.saveCapture()
            onSave(url)
            let place = url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            show("Saved \(url.lastPathComponent) to \(place) and added it to your library")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ message: String) {
        withAnimation { notice = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { if notice == message { notice = nil } }
        }
    }
}

/// "INPUT · Scarlett 2i2" picker in the top bar.
struct InputDevicePicker: View {
    @ObservedObject var capture: LiveAudioCapture
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        Menu {
            ForEach(capture.devices) { device in
                Button(action: { capture.select(device) }) {
                    if device == capture.selectedDevice {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            if capture.devices.isEmpty { Text("No audio inputs found") }
            Divider()
            Button("Refresh Inputs") { capture.refreshDevices() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic")
                Text("INPUT · \(capture.selectedDevice?.name ?? "None")")
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(theme.textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.textColor.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.textColor.opacity(0.14), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { if capture.devices.isEmpty { capture.refreshDevices() } }
        .help("Choose which input KeyFinder listens to (your macOS default is unchanged)")
    }
}
