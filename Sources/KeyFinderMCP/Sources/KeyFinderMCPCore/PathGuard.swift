import Foundation
import KeyFinderEngine

/// Errors a tool reports back to the assistant as a tool result with `isError: true`.
/// Messages are written for the user to read, since assistants usually relay them.
public enum ToolError: Error, Equatable, LocalizedError {
    case invalidArgument(String)
    case notAllowed(String)
    case notFound(String)
    case analysisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let message), .notAllowed(let message),
             .notFound(let message), .analysisFailed(let message):
            return message
        }
    }
}

/// Restricts tool access to audio inside user-approved folders. The server is read-only,
/// but an assistant can be steered by untrusted text, so paths are checked at the boundary.
public struct PathGuard: Sendable {
    public static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "flac", "aiff", "aif", "aac", "caf"]
    public static let rootsEnvironmentKey = "KEYFINDER_MCP_ROOTS"

    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    }

    /// Folders chosen in KeyFinder → Settings → AI Assistant (default `~/Music`), plus any
    /// extra folders in `KEYFINDER_MCP_ROOTS` (colon-separated, `~` allowed).
    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment,
                               access: AIFolderAccess = AIFolderAccess()) -> PathGuard {
        let extra = (environment[rootsEnvironmentKey] ?? "")
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let paths = access.effectiveFolders() + extra
        return PathGuard(roots: paths.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) })
    }

    public var rootsDescription: String {
        roots.map(\.path).joined(separator: ", ")
    }

    /// A readable audio file inside an allowed root.
    public func audioFile(_ rawPath: String) throws -> URL {
        let url = try allowedURL(rawPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ToolError.notFound("No file at \(url.path).")
        }
        guard !isDirectory.boolValue else {
            throw ToolError.invalidArgument("\(url.path) is a folder; pass an audio file.")
        }
        guard Self.audioExtensions.contains(url.pathExtension.lowercased()) else {
            throw ToolError.invalidArgument("\(url.lastPathComponent) is not a supported audio file (\(Self.audioExtensions.sorted().joined(separator: ", "))).")
        }
        return url
    }

    /// An existing folder inside an allowed root.
    public func folder(_ rawPath: String) throws -> URL {
        let url = try allowedURL(rawPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ToolError.notFound("No folder at \(url.path).")
        }
        guard isDirectory.boolValue else {
            throw ToolError.invalidArgument("\(url.path) is a file; pass a folder.")
        }
        return url
    }

    /// Audio files in `folder`, sorted by path, at most `limit`. Hidden files and package
    /// contents are skipped. `truncated` is true when more files existed.
    public func audioFiles(in folder: URL, recursive: Bool, limit: Int) -> (files: [URL], truncated: Bool) {
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: options) else {
            return ([], false)
        }
        // Collect a bounded superset so a huge library cannot stall the server, then sort
        // for deterministic results.
        let scanCap = max(limit, 1) * 4
        var found: [URL] = []
        var truncated = false
        for case let url as URL in enumerator where Self.audioExtensions.contains(url.pathExtension.lowercased()) {
            if found.count >= scanCap { truncated = true; break }
            // Resolve so paths match those from audioFile(_:), and drop symlinks that
            // lead outside the allowed roots: a listing must not widen what can be read.
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            if isInsideRoots(resolved) { found.append(resolved) }
        }
        let sorted = found.sorted { $0.path < $1.path }
        return (Array(sorted.prefix(limit)), truncated || sorted.count > limit)
    }

    private func allowedURL(_ rawPath: String) throws -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolError.invalidArgument("Path is empty.") }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            throw ToolError.invalidArgument("Use an absolute path (or one starting with ~): \(trimmed)")
        }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
        guard isInsideRoots(url) else {
            throw ToolError.notAllowed("\(url.path) is outside the folders KeyFinder may read (\(rootsDescription.isEmpty ? "none" : rootsDescription)). The user can allow it in the KeyFinder app: Settings → AI Assistant → Add Folder.")
        }
        return url
    }

    private func isInsideRoots(_ url: URL) -> Bool {
        roots.contains { root in
            url.path == root.path || url.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
        }
    }
}
