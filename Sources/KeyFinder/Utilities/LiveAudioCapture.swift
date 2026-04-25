import AVFoundation
import Accelerate
import Foundation
import KeyFinderEngine

/// Captures system audio via AVAudioEngine
/// Uses AVAudioEngine for audio input (macOS 12+)
public class LiveAudioCapture: NSObject, ObservableObject {
    @Published public var currentKey: String = "--"
    @Published public var currentBPM: String = "--"
    @Published public var isCapturing: Bool = false

    private var audioEngine: AVAudioEngine?
    private let keyDetector = KeyDetector()
    private let bpmDetector = BPMDetector()

    // Ring buffer for accumulating samples
    private var sampleBuffer: [Float] = []
    private let bufferLock = NSLock()
    private let sampleRate: Double = 44100
    private let minBufferSamples: Int = Int(44100 * 5) // 5 seconds minimum

    public override init() {
        super.init()
    }

    /// Start capturing from default system audio input
    public func startCapture() {
        let engine = AVAudioEngine()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Install tap on input node to receive audio samples
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isCapturing = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    /// Stop capturing
    public func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCapturing = false
    }

    /// Process audio buffer from AVAudioEngine
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var samples: [Float] = []
        samples.reserveCapacity(frameLength)

        // Convert to mono if stereo by averaging channels
        if channelCount == 1 {
            samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][frame]
                }
                samples.append(sum / Float(channelCount))
            }
        }

        // Accumulate samples
        bufferLock.lock()
        self.sampleBuffer.append(contentsOf: samples)
        // Keep buffer manageable
        if self.sampleBuffer.count > minBufferSamples * 4 {
            self.sampleBuffer = Array(self.sampleBuffer.suffix(minBufferSamples * 2))
        }
        let currentBufferCount = self.sampleBuffer.count
        bufferLock.unlock()

        // Process when we have enough samples
        if currentBufferCount >= minBufferSamples {
            processSamples()
        }
    }

    /// Process accumulated samples and run analysis
    private func processSamples() {
        bufferLock.lock()
        let samples = sampleBuffer
        bufferLock.unlock()

        guard samples.count >= minBufferSamples else { return }

        Task {
            let key = try? await keyDetector.detectKeyWithChanges(audioSamples: samples, sampleRate: sampleRate)
            let bpm = try? await bpmDetector.detectBPM(audioSamples: samples, sampleRate: sampleRate)

            await MainActor.run {
                self.currentKey = key?.0.shortName ?? "--"
                self.currentBPM = bpm.map { String(format: "%.1f", $0) } ?? "--"
            }
        }
    }
}
