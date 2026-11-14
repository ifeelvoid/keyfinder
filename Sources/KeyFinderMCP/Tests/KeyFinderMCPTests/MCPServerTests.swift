import Foundation
import Testing
import KeyFinderEngine
@testable import KeyFinderMCPCore

/// Returns canned analyses keyed by file name, so protocol tests need no real audio.
private struct FakeAnalyzer: TrackAnalyzing {
    let table: [String: (String, Double, Int)]

    func analyze(_ url: URL) async throws -> TrackSummary {
        guard let (camelot, bpm, energy) = table[url.lastPathComponent] else {
            throw ToolError.analysisFailed("unreadable \(url.lastPathComponent)")
        }
        return TrackSummary(path: url.path, fileName: url.lastPathComponent, key: "", camelot: camelot, bpm: bpm,
                            confidence: 0.8, energy: "", energyRank: energy, duration: 240, keyChanges: [])
    }
}

/// A temporary music root with a few empty "audio" files and one file outside the root.
private struct Fixture {
    let root: URL
    let outside: URL
    let server: MCPServer

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("kf-mcp-\(UUID().uuidString)")
        root = base.appendingPathComponent("Music")
        outside = base.appendingPathComponent("Private")
        for dir in [root, root.appendingPathComponent("sub"), outside] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for name in ["a.wav", "b.mp3", "c.flac", "sub/d.wav", "broken.wav", "notes.txt", ".hidden.wav"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try Data().write(to: outside.appendingPathComponent("secret.wav"))
        let analyzer = FakeAnalyzer(table: [
            "a.wav": ("8A", 124, 0), "b.mp3": ("9A", 125, 1), "c.flac": ("8B", 124, 2), "d.wav": ("3A", 128, 3),
            "secret.wav": ("8A", 124, 1),
        ])
        server = MCPServer(tools: ToolBox(guardrail: PathGuard(roots: [root]), analyzer: analyzer, parallelism: 2))
    }

    func call(_ method: String, _ params: JSONValue = [:], id: Int = 1) async throws -> JSONValue {
        let request: JSONValue = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params]
        let line = try #require(await server.handle(line: MCPServer.encode(request)))
        #expect(!line.contains("\n"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    func tool(_ name: String, _ arguments: JSONValue) async throws -> JSONValue {
        let response = try await call("tools/call", ["name": .string(name), "arguments": arguments])
        return try #require(response["result"])
    }
}

@Suite("MCP protocol")
struct ProtocolTests {
    @Test("initialize echoes a supported protocol version and advertises tools")
    func initialize() async throws {
        let fixture = try Fixture()
        let response = try await fixture.call("initialize", ["protocolVersion": "2025-06-18", "capabilities": [:],
                                                            "clientInfo": ["name": "test", "version": "1"]])
        #expect(response["result"]?["protocolVersion"] == "2025-06-18")
        #expect(response["result"]?["serverInfo"]?["name"] == "keyfinder")
        #expect(response["result"]?["capabilities"]?["tools"] != nil)
    }

    @Test("Unknown protocol version falls back to the newest supported")
    func initializeFallback() async throws {
        let response = try await Fixture().call("initialize", ["protocolVersion": "1999-01-01"])
        #expect(response["result"]?["protocolVersion"]?.stringValue == MCPServer.supportedProtocolVersions[0])
    }

    @Test("tools/list returns the five read-only tools")
    func toolsList() async throws {
        let response = try await Fixture().call("tools/list")
        guard case .array(let tools)? = response["result"]?["tools"] else { Issue.record("no tools"); return }
        #expect(tools.compactMap { $0["name"]?.stringValue } ==
                ["analyze_track", "analyze_folder", "find_compatible", "build_set", "fit_sample"])
        #expect(tools.allSatisfy { $0["annotations"]?["readOnlyHint"] == true })
    }

    @Test("Notifications get no reply; ping does; bad JSON is a parse error; unknown method is -32601")
    func plumbing() async throws {
        let fixture = try Fixture()
        #expect(await fixture.server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(try await fixture.call("ping")["result"] == [:])
        let parse = try #require(await fixture.server.handle(line: "{not json"))
        #expect(parse.contains("-32700"))
        #expect(try await fixture.call("resources/list")["error"]?["code"] == .number(-32601))
    }

    @Test("String ids are echoed")
    func stringId() async throws {
        let line = try #require(await Fixture().server.handle(line: #"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#))
        #expect(line.contains(#""id":"abc""#))
    }
}

@Suite("MCP tools")
struct ToolTests {
    @Test("analyze_track returns structured and text content")
    func analyzeTrack() async throws {
        let fixture = try Fixture()
        let result = try await fixture.tool("analyze_track", ["path": .string(fixture.root.appendingPathComponent("a.wav").path)])
        #expect(result["isError"] == false)
        #expect(result["structuredContent"]?["camelot"] == "8A")
        guard case .array(let content)? = result["content"] else { Issue.record("no content"); return }
        #expect(content.first?["text"]?.stringValue?.contains("8A") == true)
    }

    @Test("Paths outside the allowed roots are refused, including via ..")
    func outsideRoot() async throws {
        let fixture = try Fixture()
        for path in [fixture.outside.appendingPathComponent("secret.wav").path,
                     fixture.root.path + "/../Private/secret.wav", "/etc/passwd"] {
            let result = try await fixture.tool("analyze_track", ["path": .string(path)])
            #expect(result["isError"] == true, "\(path)")
            #expect(result["structuredContent"] == nil)
        }
    }

    @Test("Symlinks pointing outside the root are refused")
    func symlinkEscape() async throws {
        let fixture = try Fixture()
        let link = fixture.root.appendingPathComponent("link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.outside.appendingPathComponent("secret.wav"))
        let result = try await fixture.tool("analyze_track", ["path": .string(link.path)])
        #expect(result["isError"] == true)
    }

    @Test("Missing, non-audio, and bad-type arguments are tool errors, not crashes")
    func badArguments() async throws {
        let fixture = try Fixture()
        let cases: [(String, JSONValue)] = [
            ("analyze_track", [:]),
            ("analyze_track", ["path": .string(fixture.root.appendingPathComponent("notes.txt").path)]),
            ("analyze_track", ["path": .string(fixture.root.appendingPathComponent("nope.wav").path)]),
            ("analyze_track", ["path": 42]),
            ("analyze_track", ["path": "relative/a.wav"]),
            ("fit_sample", ["sample_path": .string(fixture.root.appendingPathComponent("a.wav").path),
                            "target_camelot": "13Z", "target_bpm": 124]),
            ("fit_sample", ["sample_path": .string(fixture.root.appendingPathComponent("a.wav").path),
                            "target_camelot": "8A", "target_bpm": 9000]),
            ("build_set", ["folder": .string(fixture.root.path), "energy_shape": "sideways"]),
            ("find_compatible", ["folder": .string(fixture.root.path)]),
        ]
        for (name, arguments) in cases {
            let result = try await fixture.tool(name, arguments)
            #expect(result["isError"] == true, "\(name) \(arguments)")
        }
    }

    @Test("analyze_folder: recursive, skips hidden and non-audio, reports failures")
    func analyzeFolder() async throws {
        let fixture = try Fixture()
        let result = try await fixture.tool("analyze_folder", ["path": .string(fixture.root.path)])
        guard case .array(let analyzed)? = result["structuredContent"]?["analyzed"],
              case .array(let failed)? = result["structuredContent"]?["failed"] else { Issue.record("shape"); return }
        #expect(analyzed.compactMap { $0["fileName"]?.stringValue }.sorted() == ["a.wav", "b.mp3", "c.flac", "d.wav"])
        #expect(failed.count == 1)
        #expect(failed.first?["reason"]?.stringValue?.contains("broken.wav") == true)

        let flat = try await fixture.tool("analyze_folder", ["path": .string(fixture.root.path), "recursive": false])
        guard case .array(let top)? = flat["structuredContent"]?["analyzed"] else { Issue.record("shape"); return }
        #expect(top.count == 3)
    }

    @Test("find_compatible by track excludes the reference and ranks the relative key first")
    func findCompatible() async throws {
        let fixture = try Fixture()
        let result = try await fixture.tool("find_compatible", [
            "folder": .string(fixture.root.path), "track_path": .string(fixture.root.appendingPathComponent("a.wav").path),
        ])
        guard case .array(let matches)? = result["structuredContent"]?["matches"] else { Issue.record("shape"); return }
        #expect(matches.compactMap { $0["track"]?["fileName"]?.stringValue } == ["c.flac", "b.mp3"])
    }

    @Test("build_set honours start_path and target_minutes")
    func buildSet() async throws {
        let fixture = try Fixture()
        let result = try await fixture.tool("build_set", [
            "folder": .string(fixture.root.path), "energy_shape": "peak", "target_minutes": 8,
            "start_path": .string(fixture.root.appendingPathComponent("b.mp3").path),
        ])
        guard case .array(let set)? = result["structuredContent"]?["set"] else { Issue.record("shape"); return }
        #expect(set.count == 2)  // 8 minutes of 4-minute tracks
        #expect(set.first?["track"]?["fileName"] == "b.mp3")
    }

    @Test("fit_sample with both overrides skips analysis")
    func fitSampleOverrides() async throws {
        let fixture = try Fixture()
        let result = try await fixture.tool("fit_sample", [
            "sample_path": .string(fixture.root.appendingPathComponent("broken.wav").path),
            "target_camelot": "10A", "target_bpm": 140, "sample_camelot": "8A", "sample_bpm": "70",
        ])
        #expect(result["isError"] == false)
        #expect(result["structuredContent"]?["fit"]?["semitoneShift"] == 2)
        #expect(result["structuredContent"]?["fit"]?["tempoMode"] == "half-time")
    }
}

@Suite("Path guard")
struct PathGuardTests {
    @Test("Saved folders plus env extras; default ~/Music when nothing saved")
    func currentRoots() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kf-roots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let access = AIFolderAccess(fileURL: dir.appendingPathComponent("ai-folders.json"))
        let home = NSHomeDirectory()
        #expect(PathGuard.current(environment: [:], access: access).roots.map(\.path)
                == [URL(fileURLWithPath: home + "/Music").resolvingSymlinksInPath().path])

        try access.save(["/Volumes/DJ USB"])
        let guardrail = PathGuard.current(environment: ["KEYFINDER_MCP_ROOTS": "/tmp: ~/Splice "], access: access)
        #expect(guardrail.roots.count == 3)
        #expect(guardrail.roots.first?.path == "/Volumes/DJ USB")

        try access.save([])
        #expect(PathGuard.current(environment: [:], access: access).roots.isEmpty)
    }

    @Test("Folder changes apply to the next request without a restart")
    func liveReload() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("kf-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music")
        let usb = base.appendingPathComponent("USB")
        for dir in [music, usb] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data().write(to: usb.appendingPathComponent("t.wav"))
        let access = AIFolderAccess(fileURL: base.appendingPathComponent("ai-folders.json"))
        try access.save([music.path])

        struct Fixed: TrackAnalyzing {
            func analyze(_ url: URL) async throws -> TrackSummary {
                TrackSummary(path: url.path, fileName: url.lastPathComponent, key: "", camelot: "8A", bpm: 120,
                             confidence: 1, energy: "", energyRank: 0, duration: 60, keyChanges: [])
            }
        }
        let server = MCPServer(tools: ToolBox(guardrailProvider: { PathGuard.current(environment: [:], access: access) },
                                              analyzer: Fixed()))
        let request = MCPServer.encode(["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                        "params": ["name": "analyze_track", "arguments": ["path": .string(usb.appendingPathComponent("t.wav").path)]]])
        let before = try #require(await server.handle(line: request))
        #expect(before.contains(#""isError":true"#))
        #expect(before.contains("Settings"))

        try access.save([music.path, usb.path])
        let after = try #require(await server.handle(line: request))
        #expect(after.contains(#""isError":false"#))
    }

    @Test("A sibling folder sharing a prefix is not inside the root")
    func prefixSibling() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("kf-\(UUID().uuidString)")
        let root = base.appendingPathComponent("Music")
        let sibling = base.appendingPathComponent("MusicPrivate")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data().write(to: sibling.appendingPathComponent("x.wav"))
        #expect(throws: ToolError.self) { try PathGuard(roots: [root]).audioFile(sibling.appendingPathComponent("x.wav").path) }
    }
}

@Suite("Folder listing")
struct FolderListingTests {
    @Test("Symlinks in a folder that lead outside the root are not listed")
    func symlinkInFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("kf-\(UUID().uuidString)")
        let root = base.appendingPathComponent("Music")
        let outside = base.appendingPathComponent("Private")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("in.wav"))
        try Data().write(to: outside.appendingPathComponent("secret.wav"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.wav"),
                                                   withDestinationURL: outside.appendingPathComponent("secret.wav"))
        let guardrail = PathGuard(roots: [root])
        let listing = guardrail.audioFiles(in: try guardrail.folder(root.path), recursive: true, limit: 10)
        #expect(listing.files.map(\.lastPathComponent) == ["in.wav"])
    }
}

/// Finishes in reverse order of start, so results arrive out of order.
private struct SlowAnalyzer: TrackAnalyzing {
    func analyze(_ url: URL) async throws -> TrackSummary {
        let rank = Int(url.deletingPathExtension().lastPathComponent) ?? 0
        try await Task.sleep(nanoseconds: UInt64(20 - rank) * 5_000_000)
        return TrackSummary(path: url.path, fileName: url.lastPathComponent, key: "", camelot: "8A", bpm: 120,
                            confidence: 1, energy: "", energyRank: 0, duration: 60, keyChanges: [])
    }
}

@Suite("Parallel analysis")
struct ParallelAnalysisTests {
    @Test("Out-of-order completion keeps every result with its file", arguments: [1, 3, 4, 8])
    func ordering(parallelism: Int) async throws {
        let urls = (0..<12).map { URL(fileURLWithPath: "/music/\($0).wav") }
        let box = ToolBox(guardrail: PathGuard(roots: [URL(fileURLWithPath: "/music")]), analyzer: SlowAnalyzer(),
                          parallelism: parallelism)
        let (analyzed, failed) = await box.analyzeMany(urls)
        #expect(failed.isEmpty)
        #expect(analyzed.map(\.path) == urls.map(\.path))
    }
}
