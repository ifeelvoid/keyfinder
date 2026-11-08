// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyFinderEngine",
    platforms: [.macOS(.v12)],
    products: [.library(name: "KeyFinderEngine", targets: ["KeyFinderEngine"]),
               .executable(name: "KeyFinderRegression", targets: ["KeyFinderRegression"]),
               .executable(name: "KeyFinderBenchmark", targets: ["KeyFinderBenchmark"]),
               .executable(name: "KeyFinderTempoBench", targets: ["KeyFinderTempoBench"])],
    dependencies: [],
    targets: [
        .target(name: "KeyFinderEngine", dependencies: [],
                path: "Sources/KeyFinderEngine"),
        .target(name: "RegressionFixtures", dependencies: ["KeyFinderEngine"], path: "Fixtures"),
        .executableTarget(name: "KeyFinderRegression", dependencies: ["RegressionFixtures"], path: "RegressionRunner"),
        .executableTarget(name: "KeyFinderBenchmark", dependencies: ["KeyFinderEngine"], path: "BenchmarkRunner"),
        .executableTarget(name: "KeyFinderTempoBench", dependencies: ["KeyFinderEngine"], path: "TempoBenchRunner"),
        .testTarget(name: "KeyFinderEngineTests",
                     dependencies: ["KeyFinderEngine", "RegressionFixtures"],
                     path: "Tests")
    ]
)
