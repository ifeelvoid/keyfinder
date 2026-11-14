import Foundation
import KeyFinderMCPCore

// stdout carries the MCP protocol. Anything else that writes to stdout (the engine has
// print-based debug output) would corrupt it, so keep a private handle on the real stdout
// and point file descriptor 1 at stderr before any engine code runs.
let protocolDescriptor = dup(STDOUT_FILENO)
guard protocolDescriptor >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
    FileHandle.standardError.write(Data("keyfinder-mcp: could not isolate stdout\n".utf8))
    exit(1)
}

/// Serializes writes so concurrent responses never interleave on the wire.
actor ProtocolWriter {
    private let handle = FileHandle(fileDescriptor: protocolDescriptor, closeOnDealloc: false)

    func send(_ line: String) {
        handle.write(Data((line + "\n").utf8))
    }
}

let arguments = CommandLine.arguments
if arguments.contains("--version") {
    FileHandle(fileDescriptor: protocolDescriptor).write(Data("keyfinder-mcp \(MCPServer.serverVersion)\n".utf8))
    exit(0)
}

let server = MCPServer(tools: ToolBox(guardrailProvider: { PathGuard.current() }, analyzer: EngineAnalyzer()))
let writer = ProtocolWriter()
let inFlight = DispatchGroup()
FileHandle.standardError.write(Data("keyfinder-mcp \(MCPServer.serverVersion) ready; readable folders: \(PathGuard.current().rootsDescription)\n".utf8))

// Requests run concurrently so a long folder analysis does not block ping or tools/list.
while let line = readLine(strippingNewline: true) {
    inFlight.enter()
    Task {
        if let response = await server.handle(line: line) {
            await writer.send(response)
        }
        inFlight.leave()
    }
}
inFlight.wait()
