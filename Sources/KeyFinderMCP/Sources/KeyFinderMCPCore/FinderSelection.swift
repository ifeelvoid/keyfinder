import Foundation
import KeyFinderEngine

/// The files and folders currently selected in Finder. Injected so tests need no Finder.
public protocol FinderSelecting: Sendable {
    func selectedPaths() throws -> [String]
}

/// Reads Finder's selection with a fixed AppleScript. The first call makes macOS ask the
/// user whether their assistant may control Finder.
public struct AppleScriptFinderSelection: FinderSelecting {
    static let script = """
    tell application "Finder"
        set out to ""
        repeat with anItem in (get selection)
            set out to out & POSIX path of (anItem as alias) & linefeed
        end repeat
        return out
    end tell
    """

    public init() {}

    public func selectedPaths() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", Self.script]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // Finder answers in well under a second; a hung permission prompt must not hang the tool.
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            throw ToolError.notAllowed("Finder did not answer. If macOS asked to let this assistant control Finder, click OK, then ask again.")
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Self.explain(message)
        }
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func explain(_ message: String) -> ToolError {
        if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
            return .notAllowed("This assistant is not allowed to read Finder's selection. Turn it on in System Settings → Privacy & Security → Automation (allow Finder under the assistant app), then ask again.")
        }
        if message.contains("-600") {
            return .notFound("Finder is not running.")
        }
        return .analysisFailed("Could not read Finder's selection: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}

extension ToolBox {
    static let maxSelectionFiles = 100

    struct SelectionResult: Codable, Sendable {
        let analyzed: [TrackSummary]
        let failed: [Failure]
        /// Selected items that are not audio files or folders, so were skipped.
        let skipped: [String]
        let truncated: Bool
    }

    /// The user picked these files in Finder themselves, so they are readable even outside
    /// the allowed folders. The assistant cannot choose the paths, only ask for the selection.
    func analyzeFinderSelection() async throws -> JSONValue {
        let selected = try finderSelection.selectedPaths()
        guard !selected.isEmpty else {
            throw ToolError.notFound("Nothing is selected in Finder. Select one or more audio files (or a folder) in Finder, then ask again.")
        }
        var files: [URL] = []
        var skipped: [String] = []
        var truncated = false
        for path in selected {
            let url = URL(fileURLWithPath: path)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { skipped.append(path); continue }
            // A one-root guard keeps the symlink and extension checks of the normal tools.
            if isFolder.boolValue {
                let listing = PathGuard(roots: [url]).audioFiles(in: url.resolvingSymlinksInPath(), recursive: false,
                                                                 limit: Self.maxSelectionFiles)
                files += listing.files
                truncated = truncated || listing.truncated
            } else if let file = try? PathGuard(roots: [url.deletingLastPathComponent()]).audioFile(path) {
                files.append(file)
            } else {
                skipped.append(path)
            }
        }
        if files.count > Self.maxSelectionFiles {
            files = Array(files.prefix(Self.maxSelectionFiles))
            truncated = true
        }
        guard !files.isEmpty else {
            throw ToolError.notFound("The Finder selection has no audio files (mp3, wav, m4a, flac, aiff, aac, caf).")
        }
        let (analyzed, failed) = await analyzeMany(files)
        return try JSONValue.from(SelectionResult(analyzed: analyzed, failed: failed, skipped: skipped, truncated: truncated))
    }
}
