import AudioToolbox
import CoreAudio
import Foundation

/// Input-only capture from one Core Audio device through a dedicated AUHAL unit.
///
/// AVAudioEngine shares one I/O unit between input and output, and pointing that unit at an
/// external interface (for example a Focusrite Scarlett) could start "successfully" yet never
/// deliver audio, or stall the caller. This unit has output disabled, so the output device is
/// never touched, and the client format always matches the device's real rate and channels.
///
/// Not thread-safe: call `prepare`, `start` and `stop` from one serial queue.
final class InputDeviceCapture {
    enum Failure: LocalizedError {
        case unavailable(OSStatus, String)
        case noChannels

        var errorDescription: String? {
            switch self {
            case let .unavailable(status, step): return "\(step) failed (Core Audio error \(Self.code(status)))."
            case .noChannels: return "This input has no audio channels."
            }
        }

        /// Core Audio errors are usually four letters packed into an Int32, e.g. 'stop' = device not running.
        private static func code(_ status: OSStatus) -> String {
            let bytes = withUnsafeBytes(of: UInt32(bitPattern: status).bigEndian, Array.init)
            guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return "\(status)" }
            return "'" + String(decoding: bytes, as: UTF8.self) + "'"
        }
    }

    enum Event { case disconnected, formatChanged }

    let deviceID: AudioDeviceID
    private(set) var sampleRate: Double = 0
    private var unit: AudioUnit?
    private var channels = 0
    private var maxFrames = 0
    private var bufferList: UnsafeMutableAudioBufferListPointer?
    private var channelStorage: [UnsafeMutablePointer<Float>] = []
    private var onSamples: (([Float]) -> Void)?
    private var onEvent: ((Event) -> Void)?
    private var listenerQueue: DispatchQueue?
    private var listener: AudioObjectPropertyListenerBlock?

    init(deviceID: AudioDeviceID) {
        self.deviceID = deviceID
    }

    deinit { stop() }

    /// Opens the device and returns its sample rate. Call before `start`.
    func prepare() throws -> Double {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw Failure.unavailable(-1, "Opening the audio input")
        }
        var newUnit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &newUnit), "Opening the audio input")
        guard let unit = newUnit else { throw Failure.unavailable(-1, "Opening the audio input") }
        self.unit = unit

        var on: UInt32 = 1
        var off: UInt32 = 0
        var device = deviceID
        let flagSize = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, flagSize),
                  "Enabling input")
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, flagSize),
                  "Disabling output")
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &device, UInt32(MemoryLayout<AudioDeviceID>.size)),
                  "Selecting the input")

        var hardware = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
                                       &hardware, &formatSize),
                  "Reading the input format")
        guard hardware.mChannelsPerFrame > 0, hardware.mSampleRate > 0 else { throw Failure.noChannels }

        // Input AUHAL cannot resample, so the client side must use the device's own rate.
        var client = AudioStreamBasicDescription(
            mSampleRate: hardware.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: hardware.mChannelsPerFrame, mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                       &client, formatSize),
                  "Setting the capture format")

        var frames: UInt32 = 4096
        var framesSize = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                             &frames, &framesSize)
        allocateBuffers(channels: Int(hardware.mChannelsPerFrame), frames: Int(max(frames, 4096)))

        var callback = AURenderCallbackStruct(inputProc: Self.inputCallback,
                                              inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                       &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
                  "Connecting the input")
        try check(AudioUnitInitialize(unit), "Starting the input")
        sampleRate = hardware.mSampleRate
        return sampleRate
    }

    /// `onSamples` receives mono audio on Core Audio's thread; `onEvent` arrives on `eventQueue`.
    func start(eventQueue: DispatchQueue, onSamples: @escaping ([Float]) -> Void,
               onEvent: @escaping (Event) -> Void) throws {
        guard let unit else { throw Failure.unavailable(-1, "Starting the input") }
        self.onSamples = onSamples
        self.onEvent = onEvent
        watchDevice(on: eventQueue)
        try check(AudioOutputUnitStart(unit), "Starting the input")
    }

    func stop() {
        unwatchDevice()
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        unit = nil
        onSamples = nil
        onEvent = nil
        releaseBuffers()
    }

    // MARK: - Render

    private static let inputCallback: AURenderCallback = { refCon, flags, timeStamp, bus, frameCount, _ in
        let capture = Unmanaged<InputDeviceCapture>.fromOpaque(refCon).takeUnretainedValue()
        return capture.render(flags, timeStamp, bus, frameCount)
    }

    private func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        _ timeStamp: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frameCount: UInt32) -> OSStatus {
        guard let unit, let bufferList, Int(frameCount) <= maxFrames else { return noErr }
        for index in 0..<channels {
            bufferList[index].mDataByteSize = frameCount * 4
            bufferList[index].mData = UnsafeMutableRawPointer(channelStorage[index])
        }
        let status = AudioUnitRender(unit, flags, timeStamp, bus, frameCount, bufferList.unsafeMutablePointer)
        guard status == noErr else { return status }
        let count = Int(frameCount)
        var mono = [Float](repeating: 0, count: count)
        let scale = 1 / Float(channels)
        for channel in channelStorage {
            for frame in 0..<count { mono[frame] += channel[frame] * scale }
        }
        onSamples?(mono)
        return noErr
    }

    private func allocateBuffers(channels: Int, frames: Int) {
        releaseBuffers()
        self.channels = channels
        maxFrames = frames
        channelStorage = (0..<channels).map { _ in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            pointer.initialize(repeating: 0, count: frames)
            return pointer
        }
        let list = AudioBufferList.allocate(maximumBuffers: channels)
        for index in 0..<channels {
            list[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                      mData: UnsafeMutableRawPointer(channelStorage[index]))
        }
        bufferList = list
    }

    private func releaseBuffers() {
        channelStorage.forEach { $0.deallocate() }
        channelStorage = []
        if let bufferList { free(bufferList.unsafeMutablePointer) }
        bufferList = nil
        channels = 0
        maxFrames = 0
    }

    // MARK: - Device changes

    private static let watchedSelectors = [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyNominalSampleRate]

    private func watchDevice(on queue: DispatchQueue) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let onEvent = self.onEvent else { return }
            onEvent(self.isAlive() ? .formatChanged : .disconnected)
        }
        for selector in Self.watchedSelectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, block)
        }
        listener = block
        listenerQueue = queue
    }

    private func unwatchDevice() {
        guard let listener, let listenerQueue else { return }
        for selector in Self.watchedSelectors {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, listenerQueue, listener)
        }
        self.listener = nil
        self.listenerQueue = nil
    }

    private func isAlive() -> Bool {
        var address = Self.address(kAudioDevicePropertyDeviceIsAlive)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw Failure.unavailable(status, step) }
    }
}
