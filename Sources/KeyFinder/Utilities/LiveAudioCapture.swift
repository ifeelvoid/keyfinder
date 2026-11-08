import AVFoundation
import AudioToolbox
import Foundation
import KeyFinderEngine

/// Captures the chosen audio input (macOS 12+) and re-analyzes a rolling window every few seconds.
public class LiveAudioCapture: NSObject, ObservableObject {
    @Published public var currentKey: String = "--"
    @Published public var currentBPM: String = "--"
    @Published public var currentCamelot: String?
    @Published public var isCapturing: Bool = false
    /// Seconds heard since capture started or was reset.
    @Published public var capturedSeconds: Double = 0
    /// Normalized C…B pitch-class energy behind the current key read.
    @Published public var pitchEnergy: [Double] = Array(repeating: 0, count: 12)
    /// While held, new analyses keep running but the displayed result stays frozen.
    @Published public var isHeld = false
    @Published public var statusMessage: String?
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var selectedDevice: AudioInputDevice?

    static let maxSavedSeconds = 60.0
    private static let deviceDefaultsKey = "liveInputDeviceUID"

    private var audioEngine: AVAudioEngine?
    private let analysisWindow = LiveAnalysisWindow()
    @MainActor private var analysisTask: Task<Void, Never>?
    private let recordingLock = NSLock()
    private var recording: [Float] = []
    private var recordingRate: Double = 0
    private var heardFrames = 0

    // MARK: - Devices

    @MainActor
    func refreshDevices() {
        devices = AudioInputDevice.all()
        let savedUID = UserDefaults.standard.string(forKey: Self.deviceDefaultsKey)
        selectedDevice = devices.first { $0.uid == savedUID } ?? AudioInputDevice.defaultInput() ?? devices.first
    }

    @MainActor
    func select(_ device: AudioInputDevice) {
        UserDefaults.standard.set(device.uid, forKey: Self.deviceDefaultsKey)
        selectedDevice = device
        if isCapturing {
            stopCapture()
            startCapture()
        }
    }

    // MARK: - Capture

    @MainActor
    public func startCapture() {
        guard !isCapturing else { return }
        if devices.isEmpty { refreshDevices() }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            statusMessage = "Microphone access is off. Allow KeyFinder in System Settings › Privacy & Security › Microphone."
            return
        case .notDetermined:
            // Ask first so the screen never claims to listen while macOS is still waiting for an answer.
            statusMessage = "Waiting for microphone permission…"
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.statusMessage = granted ? nil
                        : "Microphone access is off. Allow KeyFinder in System Settings › Privacy & Security › Microphone."
                    if granted { self.startCapture() }
                }
            }
            return
        default:
            break
        }
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        if var deviceID = selectedDevice?.id, let unit = inputNode.audioUnit {
            // Must happen before the input format is read.
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, analysisWindow.begin(sampleRate: format.sampleRate) else {
            statusMessage = "This input has no audio channels. Choose another input."
            return
        }
        resetRecording(sampleRate: format.sampleRate)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        do {
            try engine.start()
            audioEngine = engine
            isCapturing = true
            statusMessage = nil
            watchForSilentInput(engine)
        } catch {
            inputNode.removeTap(onBus: 0)
            analysisWindow.stop()
            statusMessage = "Could not start \(selectedDevice?.name ?? "the input"): \(error.localizedDescription)"
        }
    }

    /// macOS can start an input yet deliver nothing (for example when microphone access was
    /// refused for this build). Say so instead of showing "Listening" forever.
    @MainActor
    private func watchForSilentInput(_ engine: AVAudioEngine) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isCapturing, self.audioEngine === engine else { return }
            self.recordingLock.lock()
            let heard = self.heardFrames
            self.recordingLock.unlock()
            if heard == 0 {
                self.statusMessage = "No audio is arriving from \(self.selectedDevice?.name ?? "this input"). "
                    + "Check System Settings › Privacy & Security › Microphone, or choose another input."
            }
        }
    }

    @MainActor
    public func stopCapture() {
        analysisWindow.stop()
        analysisTask?.cancel()
        analysisTask = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCapturing = false
        clearResult()
    }

    /// Forget everything heard so far and start a fresh read on the same input.
    @MainActor
    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        if isCapturing {
            analysisWindow.begin(sampleRate: recordingRate)
            resetRecording(sampleRate: recordingRate)
        }
        clearResult()
    }

    @MainActor
    private func clearResult() {
        currentKey = "--"
        currentBPM = "--"
        currentCamelot = nil
        pitchEnergy = Array(repeating: 0, count: 12)
        capturedSeconds = 0
        isHeld = false
    }

    private func resetRecording(sampleRate: Double) {
        recordingLock.lock()
        recording.removeAll(keepingCapacity: true)
        recordingRate = sampleRate
        heardFrames = 0
        recordingLock.unlock()
    }

    // MARK: - Save

    /// ~/Music/KeyFinder Captures when macOS allows it; otherwise KeyFinder's Application Support
    /// folder, which unsigned builds can always write to.
    static func captureFolder() throws -> URL {
        let fileManager = FileManager.default
        let music = fileManager.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyFinder Captures", isDirectory: true)
        if (try? fileManager.createDirectory(at: music, withIntermediateDirectories: true)) != nil,
           fileManager.isWritableFile(atPath: music.path) {
            return music
        }
        let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyFinder/Live Captures", isDirectory: true)
        try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Writes the last `maxSavedSeconds` of captured audio as a WAV (see `captureFolder`).
    @MainActor
    func saveCapture() throws -> URL {
        recordingLock.lock()
        let samples = recording
        let rate = recordingRate
        recordingLock.unlock()
        guard rate > 0, samples.count >= Int(rate * LiveAnalysisWindow.stepSeconds) else {
            throw CaptureError.tooShort
        }
        let folder = try Self.captureFolder()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = ["Live", currentKey == "--" ? nil : currentKey, stamp.string(from: Date())]
            .compactMap { $0 }.joined(separator: " ")
        let url = folder.appendingPathComponent(name).appendingPathExtension("wav")
        try Self.writeWAV(samples, sampleRate: rate, to: url)
        return url
    }

    /// Mono 32-bit float WAV, the same audio the live analysis heard.
    static func writeWAV(_ samples: [Float], sampleRate rate: Double, to url: URL) throws {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw CaptureError.tooShort
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    enum CaptureError: LocalizedError {
        case tooShort
        var errorDescription: String? { "Capture at least 5 seconds before saving." }
    }

    // MARK: - Analysis

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData, buffer.format.channelCount > 0 else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var samples = [Float](repeating: 0, count: frameLength)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount { samples[frame] += channelData[channel][frame] }
            samples[frame] /= Float(channelCount)
        }

        recordingLock.lock()
        recording.append(contentsOf: samples)
        let keep = Int(recordingRate * Self.maxSavedSeconds)
        if recording.count > keep + Int(recordingRate) { recording.removeFirst(recording.count - keep) }
        heardFrames += frameLength
        let heard = recordingRate > 0 ? Double(heardFrames) / recordingRate : 0
        recordingLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.capturedSeconds = heard
            if self?.statusMessage?.hasPrefix("No audio is arriving") == true { self?.statusMessage = nil }
        }

        guard let work = analysisWindow.append(samples, sampleRate: buffer.format.sampleRate) else { return }
        Task { @MainActor [weak self] in
            guard let self = self, self.analysisWindow.isCurrent(work) else { return }
            self.analysisTask = Task { [weak self] in
                // A cancelled old session cannot share mutable detector state with the next.
                let detector = KeyDetector.configured(for: KeyStyle.stored())
                let key = try? await detector.detectKeyWithChanges(audioSamples: work.samples, sampleRate: work.sampleRate)
                let evidence = try? await detector.collectTonalEvidence(audioSamples: work.samples, sampleRate: work.sampleRate)
                let bpm = try? await BPMDetector().detectBPM(audioSamples: work.samples, sampleRate: work.sampleRate)
                guard let self = self, self.analysisWindow.finish(work), !Task.isCancelled else { return }
                self.analysisTask = nil
                guard !self.isHeld else { return }
                self.currentKey = key?.0.shortName ?? "--"
                self.currentCamelot = key?.0.camelotNotation
                self.currentBPM = bpm.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil } ?? "--"
                if let evidence { self.pitchEnergy = Self.averageChroma(evidence) }
            }
        }
    }

    /// Loudness-weighted mean of segment chroma, scaled so the strongest pitch class is 1.
    static func averageChroma(_ segments: [KeyDetector.TonalSegment]) -> [Double] {
        var total = Array(repeating: 0.0, count: 12)
        for segment in segments where segment.chroma.count == 12 {
            for pitch in 0..<12 { total[pitch] += segment.chroma[pitch] * segment.rms }
        }
        let peak = total.max() ?? 0
        return peak > 0 ? total.map { $0 / peak } : total
    }
}
