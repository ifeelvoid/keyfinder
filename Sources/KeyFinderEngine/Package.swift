// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyFinderEngine",
    platforms: [.macOS(.v12)],
    products: [.library(name: "KeyFinderEngine", targets: ["KeyFinderEngine"])],
    dependencies: [],
    targets: [
        .target(name: "KeyFinderEngine", dependencies: [],
                path: "Sources/KeyFinderEngine"),
        .testTarget(name: "KeyFinderEngineTests",
                     dependencies: ["KeyFinderEngine"],
                     path: "Tests")
    ]
)