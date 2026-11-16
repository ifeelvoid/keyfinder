import Foundation

/// One-click connection of `keyfinder-mcp` to AI assistants by editing each assistant's own
/// MCP config file. Only KeyFinder's entry is added, updated or removed; every other setting
/// is kept, and the original file is copied to `<name>.keyfinder-backup` before the first edit.
struct AssistantConnector {
    enum Assistant: String, CaseIterable, Identifiable {
        case claudeDesktop, chatGPT, claudeCode, cursor, vsCode

        var id: String { rawValue }

        var name: String {
            switch self {
            case .claudeDesktop: return "Claude"
            case .chatGPT: return "ChatGPT and Codex"
            case .claudeCode: return "Claude Code"
            case .cursor: return "Cursor"
            case .vsCode: return "VS Code"
            }
        }

        /// What the user has to do after connecting for the assistant to pick KeyFinder up.
        var finishStep: String {
            switch self {
            case .claudeDesktop: return "Quit and reopen Claude to finish."
            case .chatGPT: return "Quit and reopen ChatGPT (or start a new Codex session) to finish."
            case .claudeCode: return "Start a new Claude Code session to finish."
            case .cursor: return "Restart Cursor to finish."
            case .vsCode: return "Reload VS Code to finish."
            }
        }

        var bundleIdentifiers: [String] {
            switch self {
            case .claudeDesktop: return ["com.anthropic.claudefordesktop"]
            case .chatGPT: return ["com.openai.chat", "com.openai.codex"]
            case .claudeCode: return []
            case .cursor: return ["com.todesktop.230313mzl4w4u92"]
            case .vsCode: return ["com.microsoft.VSCode"]
            }
        }

        func configURL(home: URL) -> URL {
            switch self {
            case .claudeDesktop: return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
            case .chatGPT: return home.appendingPathComponent(".codex/config.toml")
            case .claudeCode: return home.appendingPathComponent(".claude.json")
            case .cursor: return home.appendingPathComponent(".cursor/mcp.json")
            case .vsCode: return home.appendingPathComponent("Library/Application Support/Code/User/mcp.json")
            }
        }
    }

    enum Status: Equatable {
        case notInstalled
        case notConnected
        case connected
        /// Connected to a different copy of the server, for example an older KeyFinder.
        case outdated(String)
        /// The config file exists but is not plain JSON/TOML KeyFinder can safely edit.
        case unreadable
    }

    enum ConnectError: LocalizedError {
        case unreadable(URL)
        case notInstalled(String)

        var errorDescription: String? {
            switch self {
            case let .unreadable(url):
                return "KeyFinder could not safely read \(url.path), so it was left unchanged. Add KeyFinder by hand using docs/AI-ASSISTANT.md."
            case let .notInstalled(name):
                return "\(name) does not appear to be installed."
            }
        }
    }

    static let serverName = "keyfinder"

    let home: URL
    let serverPath: String
    /// Whether an app with this bundle identifier is installed; injected so tests need no apps.
    let isAppInstalled: (String) -> Bool

    private var fileManager: FileManager { .default }

    func isInstalled(_ assistant: Assistant) -> Bool {
        if assistant.bundleIdentifiers.contains(where: isAppInstalled) { return true }
        let config = assistant.configURL(home: home)
        // Claude Code has no app bundle; its user config file is the sign it is installed.
        return assistant == .claudeCode ? fileManager.fileExists(atPath: config.path)
            : fileManager.fileExists(atPath: config.deletingLastPathComponent().path)
    }

    func status(_ assistant: Assistant) -> Status {
        guard isInstalled(assistant) else { return .notInstalled }
        let url = assistant.configURL(home: home)
        guard fileManager.fileExists(atPath: url.path) else { return .notConnected }
        guard let command = try? currentCommand(assistant, at: url) else { return .unreadable }
        guard let command else { return .notConnected }
        return command == serverPath ? .connected : .outdated(command)
    }

    func connect(_ assistant: Assistant) throws {
        guard isInstalled(assistant) else { throw ConnectError.notInstalled(assistant.name) }
        try edit(assistant) { assistant == .chatGPT ? Self.tomlSetting($0, command: serverPath)
                                                    : try jsonSetting($0, assistant: assistant, add: true) }
    }

    func disconnect(_ assistant: Assistant) throws {
        let url = assistant.configURL(home: home)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try edit(assistant) { assistant == .chatGPT ? Self.tomlSetting($0, command: nil)
                                                    : try jsonSetting($0, assistant: assistant, add: false) }
    }

    // MARK: - File handling

    private func edit(_ assistant: Assistant, _ transform: (Data?) throws -> Data) throws {
        let url = assistant.configURL(home: home)
        let existing = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let updated: Data
        do { updated = try transform(existing) } catch { throw ConnectError.unreadable(url) }
        guard updated != existing else { return }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = (try? fileManager.attributesOfItem(atPath: url.path))?[.posixPermissions]
        if existing != nil {
            let backup = url.appendingPathExtension("keyfinder-backup")
            if !fileManager.fileExists(atPath: backup.path) { try fileManager.copyItem(at: url, to: backup) }
        }
        try updated.write(to: url, options: .atomic)
        if let permissions { try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
    }

    private func currentCommand(_ assistant: Assistant, at url: URL) throws -> String?? {
        let data = try Data(contentsOf: url)
        if assistant == .chatGPT {
            guard let text = String(data: data, encoding: .utf8) else { throw ConnectError.unreadable(url) }
            return .some(Self.tomlCommand(in: text))
        }
        let root = try Self.jsonObject(data)
        let servers = root[Self.serversKey(assistant)] as? [String: Any]
        let entry = servers?[Self.serverName] as? [String: Any]
        return .some(entry?["command"] as? String)
    }

    // MARK: - JSON assistants

    private static func serversKey(_ assistant: Assistant) -> String {
        assistant == .vsCode ? "servers" : "mcpServers"
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private func jsonSetting(_ data: Data?, assistant: Assistant, add: Bool) throws -> Data {
        var root = try data.map(Self.jsonObject) ?? [:]
        let key = Self.serversKey(assistant)
        var servers = root[key] as? [String: Any] ?? [:]
        if add {
            var entry: [String: Any] = ["command": serverPath, "args": [String]()]
            if assistant == .claudeCode || assistant == .vsCode { entry["type"] = "stdio" }
            servers[Self.serverName] = entry
        } else {
            guard servers[Self.serverName] != nil else { return data ?? Data() }
            servers[Self.serverName] = nil
        }
        root[key] = servers
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
    }

    // MARK: - ChatGPT / Codex (TOML)

    private static let tomlHeader = "[mcp_servers.\(serverName)]"

    /// Lines of the `[mcp_servers.keyfinder]` table and its sub-tables, as a range per block.
    private static func tomlBlocks(_ lines: [String]) -> [Range<Int>] {
        var blocks: [Range<Int>] = []
        var start: Int?
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }
            let ours = line == tomlHeader || line.hasPrefix("[mcp_servers.\(serverName).")
            if let open = start, !ours { blocks.append(open..<index); start = nil }
            if ours, start == nil { start = index }
        }
        if let open = start { blocks.append(open..<lines.count) }
        return blocks
    }

    static func tomlCommand(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        for block in tomlBlocks(lines) {
            for line in lines[block] {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0] == "command" else { continue }
                return unquote(parts[1])
            }
        }
        return nil
    }

    /// Replaces KeyFinder's table with one pointing at `command`, or removes it when nil.
    static func tomlSetting(_ data: Data?, command: String?) -> Data {
        var lines = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "").components(separatedBy: "\n")
        for block in tomlBlocks(lines).reversed() { lines.removeSubrange(block) }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        if let command {
            if !lines.isEmpty { lines.append("") }
            lines += [tomlHeader, "command = \(quote(command))", "args = []"]
        }
        return Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8)
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func unquote(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespaces)
        // TOML literal strings ('...') have no escapes; basic strings ("...") escape \ and ".
        if text.hasPrefix("'"), let end = text.dropFirst().firstIndex(of: "'") {
            return String(text[text.index(after: text.startIndex)..<end])
        }
        guard text.hasPrefix("\"") else { return text }
        var result = ""
        var escaped = false
        for character in text.dropFirst() {
            if escaped { result.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { break }
            else { result.append(character) }
        }
        return result
    }
}
