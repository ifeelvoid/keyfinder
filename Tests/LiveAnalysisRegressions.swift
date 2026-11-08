import Foundation

@main
enum LiveAnalysisRegressions {
    static func main() {
        let window = LiveAnalysisWindow()
        precondition(!window.begin(sampleRate: .nan))
        precondition(window.begin(sampleRate: 48000))
        precondition(window.append([Float](repeating: 0, count: 220500), sampleRate: 48000) == nil,
                     "48 kHz input was treated as 44.1 kHz")
        let work = window.append([Float](repeating: 0, count: 19500), sampleRate: 48000)!
        precondition(work.samples.count == 240000 && work.sampleRate == 48000)
        for _ in 0..<100 {
            precondition(window.append([Float](repeating: 1, count: 4096), sampleRate: 48000) == nil,
                         "Audio callbacks scheduled overlapping analyses")
        }
        precondition(window.finish(work))
        let next = window.append([0], sampleRate: 48000)!
        precondition(next.samples.count <= 1_440_000, "Rolling window exceeded 30 seconds")
        precondition(next.samples.count > 240000, "Rolling window dropped earlier audio")
        precondition(window.finish(next))
        precondition(window.append([Float](repeating: 1, count: 239999), sampleRate: 48000) == nil,
                     "Analysis ran before five seconds of new audio")
        let rolling = window.append([1], sampleRate: 48000)!
        precondition(rolling.samples.count == 889_601, "Window did not keep all audio heard so far")
        precondition(window.finish(rolling))
        let capped = window.append([Float](repeating: 2, count: 1_440_000), sampleRate: 48000)!
        precondition(capped.samples.count == 1_440_000 && capped.samples.allSatisfy { $0 == 2 },
                     "Window did not keep exactly the latest 30 seconds")
        precondition(window.finish(capped))
        window.stop()
        precondition(!window.isCurrent(next) && !window.finish(next), "Stopped session published a stale result")
        precondition(window.append([Float](repeating: 1, count: 240000), sampleRate: 48000) == nil)
        precondition(window.begin(sampleRate: 44100))
        precondition(!window.finish(next), "Old completion affected the restarted session")
        precondition(window.append([Float](repeating: 1, count: 44100), sampleRate: 44100) == nil,
                     "Restart retained samples from a previous session")
        precondition(window.append([Float](repeating: 1, count: 220500), sampleRate: 48000) == nil,
                     "Mismatched sample rates were mixed into the current session")
        let restarted = window.append([Float](repeating: 1, count: 176400), sampleRate: 44100)!
        precondition(restarted.sampleRate == 44100 && window.finish(restarted))
        print("PASS: live analysis uses device sample rate, keeps a bounded rolling window, steps every 5 s, clears restarts and rejects stale completions")
    }
}
