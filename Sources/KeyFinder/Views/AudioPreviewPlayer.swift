import SwiftUI
import AVFoundation

class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var waveformData: [Float] = []
    @Published var isCrossfading = false

    private var audioPlayer: AVAudioPlayer?
    private var crossfadePlayer: AVAudioPlayer?  // Secondary player for crossfade
    private var timer: Timer?
    private var currentURL: URL?

    // Crossfade settings
    private let crossfadeDuration: TimeInterval = 0.5  // 500ms crossfade
    private var crossfadeTimer: Timer?
    private var crossfadeStartTime: TimeInterval = 0

    func loadAudio(from url: URL, autoPlay: Bool = false) {
        // Check if we're already playing and need to crossfade
        if isPlaying && currentURL != nil && currentURL != url {
            crossfadeToNewTrack(url: url)
        } else {
            // Stop current playback
            stop()

            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.prepareToPlay()
                audioPlayer?.volume = 1.0
                duration = audioPlayer?.duration ?? 0
                currentURL = url

                // Generate waveform
                generateWaveform(from: url)

                if autoPlay {
                    play()
                }
            } catch {
                print("Error loading audio: \(error)")
            }
        }
    }

    /// Crossfade between current track and new track
    private func crossfadeToNewTrack(url: URL) {
        guard let currentPlayer = audioPlayer else {
            loadAudio(from: url, autoPlay: true)
            return
        }

        isCrossfading = true

        // Save current position
        let savedPosition = currentPlayer.currentTime

        // Create new player
        do {
            crossfadePlayer = try AVAudioPlayer(contentsOf: url)
            crossfadePlayer?.prepareToPlay()
            crossfadePlayer?.volume = 0.0
            crossfadePlayer?.currentTime = savedPosition

            // Start both players
            currentPlayer.play()
            crossfadePlayer?.play()

            crossfadeStartTime = Date().timeIntervalSince1970
            startCrossfadeTimer()
        } catch {
            print("Error crossfading: \(error)")
            loadAudio(from: url, autoPlay: true)
        }
    }

    private func startCrossfadeTimer() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self,
                  let currentPlayer = self.audioPlayer,
                  let newPlayer = self.crossfadePlayer else { return }

            let elapsed = Date().timeIntervalSince1970 - self.crossfadeStartTime
            let progress = min(elapsed / self.crossfadeDuration, 1.0)

            // Linear crossfade: fade out current, fade in new
            currentPlayer.volume = Float(1.0 - progress)
            newPlayer.volume = Float(progress)

            if progress >= 1.0 {
                // Crossfade complete
                self.crossfadeTimer?.invalidate()
                currentPlayer.stop()
                self.audioPlayer = newPlayer
                self.crossfadePlayer = nil
                self.duration = newPlayer.duration
                self.isCrossfading = false

                // The secondary reference was cleared above; use the player we retained.
                self.currentURL = newPlayer.url
            }
        }
    }

    func togglePlayPause() {
        guard let player = audioPlayer else { return }

        if isPlaying {
            player.pause()
            timer?.invalidate()
            isPlaying = false
        } else {
            player.play()
            startTimer()
            isPlaying = true
        }
    }

    func play() {
        audioPlayer?.play()
        startTimer()
        isPlaying = true
    }

    func pause() {
        audioPlayer?.pause()
        timer?.invalidate()
        isPlaying = false
    }

    func stop() {
        crossfadeTimer?.invalidate()
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlayer?.volume = 1.0
        crossfadePlayer?.stop()
        crossfadePlayer = nil
        timer?.invalidate()
        isPlaying = false
        isCrossfading = false
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime

            // Auto-stop when finished
            if !player.isPlaying && self.isPlaying && !self.isCrossfading {
                self.stop()
            }
        }
    }

    private func generateWaveform(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let audioFile = try AVAudioFile(forReading: url)
                let format = audioFile.processingFormat
                let frameCount = UInt32(audioFile.length)

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    return
                }

                try audioFile.read(into: buffer)

                // Downsample to ~200 points for waveform display
                let targetSamples = 200
                let step = max(1, Int(frameCount) / targetSamples)
                var waveform: [Float] = []

                guard let floatData = buffer.floatChannelData else { return }
                let channelData = floatData[0]

                for i in stride(from: 0, to: Int(frameCount), by: step) {
                    // Calculate RMS for this chunk
                    var sum: Float = 0
                    let chunkSize = min(step, Int(frameCount) - i)
                    for j in 0..<chunkSize {
                        let sample = channelData[i + j]
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(chunkSize))
                    waveform.append(rms)
                }

                DispatchQueue.main.async {
                    self.waveformData = waveform
                }
            } catch {
                print("Error generating waveform: \(error)")
            }
        }
    }

    deinit {
        stop()
    }
}

struct AudioPreviewPlayer: View {
    let track: TrackAnalysis
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var playerManager = AudioPlayerManager()

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.tertiaryTextColor)
                Text("AUDIO PREVIEW")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
                Spacer()
                Text("\(formatTime(playerManager.currentTime)) / \(formatTime(playerManager.duration))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(themeManager.tertiaryTextColor)
            }

            // Waveform with playhead
            waveformView

            // Playback controls
            HStack(spacing: 12) {
                Button(action: { playerManager.togglePlayPause() }) {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(themeManager.textColor)
                }
                .buttonStyle(.plain)

                Button(action: { playerManager.stop() }) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(themeManager.surfaceColor.opacity(0.5))
        .cornerRadius(4)
        .onAppear {
            playerManager.loadAudio(from: track.filePath)
        }
        .onDisappear {
            playerManager.stop()
        }
    }

    private var waveformView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(themeManager.surfaceColor)
                    .frame(height: 60)
                    .cornerRadius(2)

                // Waveform bars
                HStack(spacing: 1) {
                    ForEach(Array(playerManager.waveformData.enumerated()), id: \.offset) { index, amplitude in
                        Rectangle()
                            .fill(waveformColor(for: index, geometry: geometry))
                            .frame(width: max(1, geometry.size.width / CGFloat(playerManager.waveformData.count) - 1))
                            .frame(height: max(2, CGFloat(amplitude) * 60))
                    }
                }
                .frame(height: 60, alignment: .center)

                // Playhead
                if playerManager.duration > 0 {
                    Rectangle()
                        .fill(themeManager.textColor.opacity(0.8))
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
        .frame(height: 60)
    }

    private func waveformColor(for index: Int, geometry: GeometryProxy) -> Color {
        let position = CGFloat(index) / CGFloat(playerManager.waveformData.count)
        let currentPosition = playerManager.currentTime / playerManager.duration

        if position <= currentPosition {
            return themeManager.textColor
        } else {
            return themeManager.tertiaryTextColor.opacity(0.5)
        }
    }

    private func playheadPosition(in width: CGFloat) -> CGFloat {
        guard playerManager.duration > 0 else { return 0 }
        return (playerManager.currentTime / playerManager.duration) * width
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
