import Foundation

@main
enum CrateRoundTrip {
    static func main() throws {
        var track = TrackAnalysis(fileName: "A & B.wav", filePath: URL(fileURLWithPath: "/tmp/A & B.wav"))
        track.key = "Am"; track.camelotNotation = "8A"; track.bpm = "120"
        track.detectedKey = "C"; track.detectedCamelot = "8B"
        track.duration = 80
        track.artist = "Test artist"; track.comment = "Manual correction"
        track.analysisFingerprint = "fixture"
        var cue = CuePoint(timestamp: 16, name: "Energy rise")
        cue.isSuggested = true
        track.cuePoints = [cue, CuePoint(timestamp: 32, name: "Confirmed cue")]
        track.beatGrid = BeatGridData(bpm: 120, timeSignature: "4/4", firstDownbeatTime: 0,
                                     beats: [.init(time: 0, strength: 1, isDownbeat: true, beatNumber: 1)])
        let decoded = try JSONDecoder().decode([TrackAnalysis].self, from: JSONEncoder().encode([track]))[0]
        precondition(decoded.id == track.id && decoded.key == "Am" && decoded.detectedKey == "C")
        precondition(decoded.cuePoints.count == 2 && decoded.cuePoints[0].isSuggested && !decoded.cuePoints[1].isSuggested)
        precondition(decoded.beatGrid?.beats.count == 1 && decoded.comment == track.comment && decoded.analysisFingerprint == "fixture")
        precondition(!decoded.isAnalyzing && !decoded.hasError)
        print("PASS: crate preserves corrections, detected values, cues, approval state and beat grid")
    }
}
