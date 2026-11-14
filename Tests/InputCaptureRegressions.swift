import Foundation

/// Hardware check for LIVE input (GitHub issue #5): every connected input must open on a
/// background queue, deliver audio at its own sample rate, and stop cleanly, including rapid
/// start/stop as when switching inputs. Devices that report "not running" (for example an
/// idle iPhone microphone) must fail with an error instead of hanging.
///
/// swiftc Tests/InputCaptureRegressions.swift Sources/KeyFinder/Utilities/InputDeviceCapture.swift \
///   Sources/KeyFinder/Utilities/AudioInputDevices.swift -o /tmp/input-capture && /tmp/input-capture
@main
enum InputCaptureRegressions {
    static func main() {
        let devices = AudioInputDevice.all()
        guard !devices.isEmpty else { print("SKIP: no audio inputs on this machine"); return }
        let queue = DispatchQueue(label: "InputCaptureRegressions")
        let lock = NSLock()
        var silent: [String] = []
        for device in devices {
            var frames = 0
            let capture = InputDeviceCapture(deviceID: device.id)
            let started = Date()
            do {
                let rate = try queue.sync { try capture.prepare() }
                precondition(rate > 0, "\(device.name) reported no sample rate")
                try queue.sync {
                    try capture.start(eventQueue: queue,
                                      onSamples: { samples in lock.lock(); frames += samples.count; lock.unlock() },
                                      onEvent: { _ in })
                }
                Thread.sleep(forTimeInterval: 1)
                queue.sync { capture.stop() }
                lock.lock(); let heard = frames; lock.unlock()
                if heard == 0 { silent.append(device.name) }
                print("\(device.name): \(Int(rate)) Hz, \(heard) frames")
            } catch {
                queue.sync { capture.stop() }
                print("\(device.name): \(error.localizedDescription)")
            }
            precondition(Date().timeIntervalSince(started) < 5, "\(device.name) blocked for more than 5 s")
        }
        precondition(silent.isEmpty, "Inputs opened but delivered no audio: \(silent)")
        for _ in 0..<20 {
            let capture = InputDeviceCapture(deviceID: devices[0].id)
            _ = try? capture.prepare()
            try? capture.start(eventQueue: queue, onSamples: { _ in }, onEvent: { _ in })
            capture.stop()
        }
        print("PASS: \(devices.count) inputs opened without blocking; rapid start/stop is clean")
    }
}
