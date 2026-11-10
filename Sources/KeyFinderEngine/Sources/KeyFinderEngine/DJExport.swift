import Foundation

public struct DJExportTrack {
    public var path: URL
    public var name: String
    public var artist: String
    public var key: String
    public var bpm: Double
    public var duration: Double
    public var cues: [CueSuggestion]
    public var firstDownbeat: Double?
    public var meter: String
    public init(path: URL, name: String, artist: String, key: String, bpm: Double, duration: Double,
                cues: [CueSuggestion], firstDownbeat: Double? = nil, meter: String = "4/4") {
        self.path = path; self.name = name; self.artist = artist; self.key = key
        self.bpm = bpm; self.duration = duration; self.cues = cues
        self.firstDownbeat = firstDownbeat; self.meter = meter
    }
}

public enum DJExport {
    public static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }

    private static func element(_ name: String, _ attributes: [String: String] = [:]) -> XMLElement {
        let result = XMLElement(name: name)
        for key in attributes.keys.sorted() {
            result.addAttribute(XMLNode.attribute(withName: key, stringValue: attributes[key]!) as! XMLNode)
        }
        return result
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func valid(_ tracks: [DJExportTrack]) -> [DJExportTrack] {
        tracks.filter { $0.path.isFileURL && $0.bpm.isFinite && $0.bpm > 0 && $0.duration.isFinite && $0.duration > 0 }
    }

    private static func cues(_ track: DJExportTrack) -> [CueSuggestion] {
        Array(track.cues.filter { $0.time.isFinite && $0.time >= 0 && $0.time < track.duration }
            .sorted { $0.time < $1.time }.prefix(8))
    }

    private static func serialize(_ root: XMLElement) -> String {
        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return document.xmlString(options: .nodePrettyPrint)
    }

    /// Based on AlphaTheta's public XML format. Cue times and tempo offsets are seconds.
    public static func rekordbox(_ tracks: [DJExportTrack]) -> String {
        let tracks = valid(tracks)
        let root = element("DJ_PLAYLISTS", ["Version": "1.0.0"])
        root.addChild(element("PRODUCT", ["Name": "KeyFinder", "Version": "3.0", "Company": "IFEELVOID"]))
        let collection = element("COLLECTION", ["Entries": String(tracks.count)])
        root.addChild(collection)
        for (index, track) in tracks.enumerated() {
            var components = URLComponents(url: track.path, resolvingAgainstBaseURL: false)!
            components.host = "localhost"
            let entry = element("TRACK", ["TrackID": String(index + 1), "Name": track.name,
                "Artist": track.artist, "Tonality": track.key, "AverageBpm": number(track.bpm),
                "TotalTime": String(Int(track.duration)), "Location": components.string!])
            if let first = track.firstDownbeat, first.isFinite, first >= 0, first < track.duration {
                entry.addChild(element("TEMPO", ["Inizio": number(first), "Bpm": number(track.bpm), "Metro": track.meter, "Battito": "1"]))
            }
            for (slot, cue) in cues(track).enumerated() {
                entry.addChild(element("POSITION_MARK", ["Name": cue.name, "Type": "0", "Start": number(cue.time), "Num": String(slot)]))
            }
            collection.addChild(entry)
        }
        let playlists = element("PLAYLISTS")
        let folder = element("NODE", ["Type": "0", "Name": "ROOT", "Count": "1"])
        let playlist = element("NODE", ["Type": "1", "Name": "KeyFinder", "KeyType": "0", "Entries": String(tracks.count)])
        for index in tracks.indices { playlist.addChild(element("TRACK", ["Key": String(index + 1)])) }
        folder.addChild(playlist); playlists.addChild(folder); root.addChild(playlists)
        return serialize(root)
    }

    /// NML collection export. Validate in Traktor before claiming native integration.
    public static func traktor(_ tracks: [DJExportTrack]) -> String {
        let tracks = valid(tracks)
        let root = element("NML", ["VERSION": "19"])
        root.addChild(element("HEAD", ["COMPANY": "IFEELVOID", "PROGRAM": "KeyFinder"]))
        let collection = element("COLLECTION", ["ENTRIES": String(tracks.count)])
        root.addChild(collection)
        for track in tracks {
            let entry = element("ENTRY", ["TITLE": track.name, "ARTIST": track.artist])
            // NML path components use /: separators, not file:// URLs.
            let parent = track.path.deletingLastPathComponent().path
            let directory = parent.split(separator: "/").map { "/:" + $0 }.joined() + "/:"
            entry.addChild(element("LOCATION", ["DIR": directory, "FILE": track.path.lastPathComponent, "VOLUME": ""]))
            entry.addChild(element("INFO", ["KEY": track.key, "PLAYTIME": String(Int(track.duration))]))
            entry.addChild(element("TEMPO", ["BPM": number(track.bpm)]))
            for (slot, cue) in cues(track).enumerated() {
                entry.addChild(element("CUE_V2", ["NAME": cue.name, "DISPL_ORDER": String(slot), "TYPE": "0", "START": number(cue.time * 1000), "LEN": "0", "REPEATS": "-1", "HOTCUE": String(slot)]))
            }
            collection.addChild(entry)
        }
        return serialize(root)
    }
}
