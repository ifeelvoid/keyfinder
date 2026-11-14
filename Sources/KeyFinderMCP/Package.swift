// swift-tools-version: 5.9
import PackageDescription

// Stdio MCP server exposing KeyFinderEngine to AI assistants.
// Its own package so the app's root manifest is untouched and the server has no
// dependencies beyond the engine.
let package = Package(
    name: "KeyFinderMCP",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "keyfinder-mcp", targets: ["keyfinder-mcp"])
    ],
    dependencies: [
        .package(name: "KeyFinderEngine", path: "../KeyFinderEngine")
    ],
    targets: [
        .target(
            name: "KeyFinderMCPCore",
            dependencies: [.product(name: "KeyFinderEngine", package: "KeyFinderEngine")]),
        .executableTarget(
            name: "keyfinder-mcp",
            dependencies: ["KeyFinderMCPCore"]),
        .testTarget(
            name: "KeyFinderMCPTests",
            dependencies: ["KeyFinderMCPCore"])
    ]
)
