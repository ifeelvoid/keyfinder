// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyFinder",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "KeyFinder",
            targets: ["KeyFinder"])
    ],
    dependencies: [
        .package(name: "KeyFinderEngine", path: "./Sources/KeyFinderEngine")
    ],
    targets: [
        .executableTarget(
            name: "KeyFinder",
            dependencies: [.product(name: "KeyFinderEngine", package: "KeyFinderEngine")],
            resources: [.process("Resources")]
        )
    ]
)
