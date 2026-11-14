import Foundation

/// The folders AI assistants may read through `keyfinder-mcp`.
///
/// KeyFinder.app writes this list from Settings → AI Assistant; the MCP server re-reads it on
/// every request. A file is used instead of only `KEYFINDER_MCP_ROOTS` because desktop
/// assistants (ChatGPT, Claude) do not pass the user's shell environment to plugin servers.
public struct AIFolderAccess: Sendable {
    private struct Stored: Codable {
        let version: Int
        let folders: [String]
    }

    public let fileURL: URL

    public init(fileURL: URL = AIFolderAccess.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("KeyFinder/ai-folders.json")
    }

    /// Used until the user saves a list.
    public static var defaultFolders: [String] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music").path]
    }

    /// Saved folders, or nil when the user never saved a list (or it is unreadable).
    /// An empty array is a valid choice: no folder may be read.
    public func load() -> [String]? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return stored.folders
    }

    /// Saved folders, falling back to the defaults.
    public func effectiveFolders() -> [String] {
        load() ?? Self.defaultFolders
    }

    /// Writes `folders` (absolute, de-duplicated, order kept) atomically.
    public func save(_ folders: [String]) throws {
        let cleaned = Self.normalize(folders)
        let data = try JSONEncoder.pretty.encode(Stored(version: 1, folders: cleaned))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    static func normalize(_ folders: [String]) -> [String] {
        var seen = Set<String>()
        return folders
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { NSString(string: $0).expandingTildeInPath }
            // Reject relative paths before URL(fileURLWithPath:) resolves them against
            // whatever the current directory happens to be.
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { seen.insert($0).inserted }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
