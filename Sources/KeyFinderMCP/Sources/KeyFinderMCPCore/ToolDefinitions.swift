import Foundation

/// The tool list advertised in `tools/list`. Descriptions are written for the model:
/// they say when to use each tool and what comes back.
enum ToolDefinitions {
    static let readOnly: JSONValue = ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]

    static func all(rootsDescription: String) -> [JSONValue] {
        let rootsNote = " Paths must be absolute (or start with ~) and inside: \(rootsDescription)."
        return [
            tool("analyze_track", "Analyze track",
                 "Detect the musical key (with Camelot notation), BPM, confidence, energy level, duration and key changes of one audio file. Results are cached until the file changes." + rootsNote,
                 properties: ["path": string("Absolute path to an audio file (mp3, wav, m4a, flac, aiff, aac, caf).")],
                 required: ["path"]),
            tool("analyze_folder", "Analyze folder",
                 "Analyze every audio file in a folder. Use before asking for mixes or sets so the user sees what is in the folder. Files that cannot be read are listed under `failed` with a reason." + rootsNote,
                 properties: [
                    "path": string("Absolute path to a folder."),
                    "recursive": boolean("Include subfolders. Default true."),
                    "limit": integer("Maximum files to analyze, 1-\(ToolBox.maxFolderFiles). Default 200."),
                 ],
                 required: ["path"]),
            tool("find_compatible", "Find compatible tracks",
                 "List tracks in a folder that mix harmonically out of a reference track (same key, relative major/minor, or one step around the Camelot wheel) within a BPM tolerance, best first. Give either `track_path`, or `camelot` plus `bpm`. Half- and double-time count as tempo matches." + rootsNote,
                 properties: [
                    "folder": string("Folder to search."),
                    "track_path": string("Reference track. Overrides camelot/bpm."),
                    "camelot": string("Reference key in Camelot notation, e.g. 8A."),
                    "bpm": number("Reference tempo."),
                    "bpm_tolerance": number("Allowed tempo difference in percent. Default 6."),
                    "limit": integer("Maximum matches returned. Default 25."),
                    "recursive": boolean("Include subfolders. Default true."),
                 ],
                 required: ["folder"]),
            tool("build_set", "Build DJ set",
                 "Order tracks from a folder into a harmonic DJ set following an energy shape: `build` (rises to the end), `flat`, or `peak` (rises to about two-thirds in, then comes down). Each transition explains the key move and tempo change; key clashes are labelled. Deterministic for the same folder." + rootsNote,
                 properties: [
                    "folder": string("Folder of candidate tracks."),
                    "energy_shape": .object(["type": "string", "enum": ["build", "flat", "peak"], "description": "Default build."]),
                    "max_tracks": integer("Maximum tracks in the set. Default 20."),
                    "target_minutes": number("Approximate set length in minutes; overrides max_tracks."),
                    "start_path": string("Track to open the set with (must be in the folder)."),
                    "recursive": boolean("Include subfolders. Default true."),
                 ],
                 required: ["folder"]),
            tool("fit_sample", "Fit sample to project",
                 "Work out how to make a sample or loop fit a project: semitones to transpose (shortest move, relative keys count as matches), time-stretch ratio, and whether to use it at half- or double-time. Detected key/BPM of short loops can be unreliable, so pass `sample_camelot` / `sample_bpm` when the user knows them." + rootsNote,
                 properties: [
                    "sample_path": string("Absolute path to the sample."),
                    "target_camelot": string("Project key in Camelot notation, e.g. 8A."),
                    "target_bpm": number("Project tempo."),
                    "sample_camelot": string("Override the sample's detected key."),
                    "sample_bpm": number("Override the sample's detected tempo."),
                 ],
                 required: ["sample_path", "target_camelot", "target_bpm"]),
        ]
    }

    private static func tool(_ name: String, _ title: String, _ description: String,
                             properties: [String: JSONValue], required: [String]) -> JSONValue {
        [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": [
                "type": "object",
                "properties": .object(properties),
                "required": .array(required.map { .string($0) }),
                "additionalProperties": false,
            ],
            "annotations": readOnly,
        ]
    }

    private static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    private static func number(_ description: String) -> JSONValue {
        ["type": "number", "description": .string(description)]
    }

    private static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }

    private static func boolean(_ description: String) -> JSONValue {
        ["type": "boolean", "description": .string(description)]
    }
}
