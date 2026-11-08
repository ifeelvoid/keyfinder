import Foundation
import AVFoundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/fixtures"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let rate = 22050.0
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
for (name, frequencies, bpm) in [("Fixture C Major 120.wav", [261.625565, 329.627557, 391.995436], 120.0),
                                 ("Fixture G Major 122.wav", [195.997718, 246.94165, 293.664768], 122.0)] {
    let url = URL(fileURLWithPath: output).appendingPathComponent(name)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768)!
    let total = Int(48 * rate)
    var offset = 0
    while offset < total {
        let count = min(32768, total - offset)
        buffer.frameLength = AVAudioFrameCount(count)
        for i in 0..<count {
            let time = Double(offset + i) / rate
            let amplitude = time < 16 ? 0.06 : time < 32 ? 0.35 : 0.1
            let root = sin(2 * .pi * frequencies[0] * time) * 0.6
            let third = sin(2 * .pi * frequencies[1] * time) * 0.2
            let fifth = sin(2 * .pi * frequencies[2] * time) * 0.2
            let beat = time.truncatingRemainder(dividingBy: 60 / bpm)
            let click = beat < 0.01 ? exp(-beat * 500) * 0.5 : 0
            buffer.floatChannelData![0][i] = Float((root + third + fifth) * amplitude + click)
        }
        try file.write(from: buffer)
        offset += count
    }
    print(url.path)
}
