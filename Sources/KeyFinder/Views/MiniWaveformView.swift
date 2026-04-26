import SwiftUI
import AVFoundation

struct MiniWaveformView: View {
    let filePath: URL
    let beatGrid: BeatGridData?  // Optional beatgrid for overlay
    @EnvironmentObject var themeManager: ThemeManager
    @State private var waveformData: [Float] = []
    @State private var duration: TimeInterval = 0

    // Higher resolution sample count for better detail
    private let targetSamples = 100

    // Convenience initializer that accepts TrackAnalysis
    init(track: TrackAnalysis) {
        self.filePath = track.filePath
        self.beatGrid = track.beatGrid
    }

    init(filePath: URL, beatGrid: BeatGridData?) {
        self.filePath = filePath
        self.beatGrid = beatGrid
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Waveform bars
                HStack(spacing: 0.5) {
                    ForEach(Array(waveformData.enumerated()), id: \.offset) { index, amplitude in
                        Rectangle()
                            .fill(themeManager.accentColor.opacity(0.6))
                            .frame(width: max(0.5, geometry.size.width / CGFloat(waveformData.count) - 0.5))
                            .frame(height: max(1, CGFloat(amplitude) * geometry.size.height))
                    }
                }
                .frame(height: geometry.size.height, alignment: .center)

                // Beatgrid overlay
                if let grid = beatGrid, grid.hasValidGrid, duration > 0 {
                    MiniBeatGridView(beatGrid: grid, width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .onAppear {
            generateWaveform()
        }
    }

    private func generateWaveform() {
        DispatchQueue.global(qos: .utility).async {
            do {
                let audioFile = try AVAudioFile(forReading: filePath)
                let format = audioFile.processingFormat
                let sampleRate = format.sampleRate
                let frameCount = AVAudioFrameCount(audioFile.length)

                duration = Double(frameCount) / sampleRate

                // Use higher sample count for better detail
                let step = max(1, Int(frameCount) / targetSamples)
                let chunkSize = min(4096, step)

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkSize)) else {
                    return
                }

                var waveform: [Float] = []

                for i in stride(from: 0, to: Int(frameCount), by: step) {
                    // Seek to position
                    audioFile.framePosition = AVAudioFramePosition(i)

                    // Read small chunk
                    try audioFile.read(into: buffer, frameCount: AVAudioFrameCount(min(chunkSize, Int(frameCount) - i)))

                    // Calculate RMS for this chunk
                    guard let floatData = buffer.floatChannelData else { continue }
                    let channelData = floatData[0]
                    let actualFrames = Int(buffer.frameLength)

                    // Calculate both RMS and peak for better visualization
                    var sum: Float = 0
                    var peak: Float = 0
                    for j in 0..<actualFrames {
                        let sample = abs(channelData[j])
                        sum += sample * sample
                        if sample > peak {
                            peak = sample
                        }
                    }
                    let rms = sqrt(sum / Float(actualFrames))
                    // Combine RMS and peak for more visual impact
                    let combined = (rms + peak) / 2.0
                    waveform.append(combined)
                }

                // Normalize with better dynamic range
                if let maxValue = waveform.max(), maxValue > 0 {
                    waveform = waveform.map { min(1.0, $0 / maxValue * 1.2) }
                }

                DispatchQueue.main.async {
                    self.waveformData = waveform
                }
            } catch {
                // Silently fail for mini waveform
            }
        }
    }
}
