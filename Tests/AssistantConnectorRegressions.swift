import Foundation

/// One-click assistant connection must add only KeyFinder's entry, keep everything else,
/// back up the original, update an outdated path, disconnect cleanly, and refuse to edit a
/// file it cannot parse.
///
/// swiftc Tests/AssistantConnectorRegressions.swift Sources/KeyFinder/Utilities/AssistantConnector.swift \
///   -o /tmp/assistant-connector && /tmp/assistant-connector
@main
enum AssistantConnectorRegressions {
    static func main() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("kf-connector-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let server = "/Applications/KeyFinder.app/Contents/MacOS/keyfinder-mcp"
        let installed: Set<String> = ["com.anthropic.claudefordesktop", "com.openai.chat", "com.microsoft.VSCode"]
        let connector = AssistantConnector(home: home, serverPath: server, isAppInstalled: installed.contains)
        typealias A = AssistantConnector.Assistant

        func write(_ text: String, _ assistant: A) throws {
            let url = assistant.configURL(home: home)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func read(_ assistant: A) -> String { try! String(contentsOf: assistant.configURL(home: home), encoding: .utf8) }
        func json(_ assistant: A) -> [String: Any] {
            try! JSONSerialization.jsonObject(with: Data(read(assistant).utf8)) as! [String: Any]
        }

        // Not installed: Cursor (no app, no ~/.cursor) and Claude Code (no ~/.claude.json).
        precondition(connector.status(.cursor) == .notInstalled)
        precondition(connector.status(.claudeCode) == .notInstalled)
        do { try connector.connect(.cursor); preconditionFailure("connected a missing app") } catch {}

        // Claude Desktop with no config file yet: connect creates it.
        precondition(connector.status(.claudeDesktop) == .notConnected)
        try connector.connect(.claudeDesktop)
        precondition(connector.status(.claudeDesktop) == .connected)
        let claude = json(.claudeDesktop)["mcpServers"] as! [String: Any]
        precondition((claude["keyfinder"] as! [String: Any])["command"] as? String == server)
        precondition(read(.claudeDesktop).contains("/Applications/KeyFinder.app"), "slashes were escaped")

        // Claude Code: other servers and unrelated settings survive; backup is made; perms kept.
        try write(#"{"numStartups": 3, "mcpServers": {"vercel": {"type": "http", "url": "https://example.test"}}, "projects": {"/a": {"x": true}}}"#, .claudeCode)
        let claudeCodeURL = A.claudeCode.configURL(home: home)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claudeCodeURL.path)
        precondition(connector.status(.claudeCode) == .notConnected)
        try connector.connect(.claudeCode)
        let code = json(.claudeCode)
        let codeServers = code["mcpServers"] as! [String: Any]
        precondition(codeServers["vercel"] != nil && code["numStartups"] as? Int == 3 && code["projects"] != nil)
        precondition((codeServers["keyfinder"] as! [String: Any])["type"] as? String == "stdio")
        precondition(fm.fileExists(atPath: claudeCodeURL.path + ".keyfinder-backup"), "no backup")
        precondition(((try? fm.attributesOfItem(atPath: claudeCodeURL.path))?[.posixPermissions] as? Int) == 0o600, "permissions changed")
        try connector.disconnect(.claudeCode)
        let afterDisconnect = json(.claudeCode)["mcpServers"] as! [String: Any]
        precondition(afterDisconnect["keyfinder"] == nil && afterDisconnect["vercel"] != nil)
        precondition(connector.status(.claudeCode) == .notConnected)

        // ChatGPT / Codex TOML: an outdated table (with a sub-table) is replaced, others kept.
        try write("""
        model = "gpt-5"

        [mcp_servers.keyfinder]
        command = "/old/KeyFinder.app/Contents/MacOS/keyfinder-mcp"

        [mcp_servers.keyfinder.env]
        A = "1"

        [mcp_servers.vercel]
        url = "https://example.test"
        """, .chatGPT)
        precondition(connector.status(.chatGPT) == .outdated("/old/KeyFinder.app/Contents/MacOS/keyfinder-mcp"))
        try connector.connect(.chatGPT)
        let toml = read(.chatGPT)
        precondition(connector.status(.chatGPT) == .connected)
        precondition(toml.contains("model = \"gpt-5\"") && toml.contains("[mcp_servers.vercel]") && toml.contains("url = \"https://example.test\""))
        precondition(!toml.contains("/old/") && !toml.contains("keyfinder.env"))
        precondition(toml.components(separatedBy: "[mcp_servers.keyfinder]").count == 2, "duplicate table")
        try connector.connect(.chatGPT)
        precondition(read(.chatGPT) == toml, "connecting twice changed the file")
        try connector.disconnect(.chatGPT)
        precondition(!(read(.chatGPT)).contains("keyfinder") && (read(.chatGPT)).contains("[mcp_servers.vercel]"))

        // VS Code uses "servers"; a file with comments (JSONC) is refused, not rewritten.
        try write("{\n  // my servers\n  \"servers\": {}\n}\n", .vsCode)
        let original = read(.vsCode)
        precondition(connector.status(.vsCode) == .unreadable)
        do { try connector.connect(.vsCode); preconditionFailure("rewrote an unreadable file") } catch {}
        precondition(read(.vsCode) == original, "unreadable file was changed")
        try write("{\"servers\": {}}", .vsCode)
        try connector.connect(.vsCode)
        precondition(((json(.vsCode)["servers"] as! [String: Any])["keyfinder"]) != nil)

        print("PASS: connect, update, disconnect, backups, permissions and unreadable files across all assistants")
    }
}
