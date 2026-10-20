// swift-tools-version: 6.2
import PackageDescription

/// Strict settings shared by every first-party target.
let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI targets run on the main actor by default (Swift 6.2 approachable concurrency).
let ui: [SwiftSetting] = strict + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "TaellmiKit",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AppComposition", targets: ["AppComposition"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.17.7"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.1.1"),
    ],
    targets: [
        // MARK: Core (no third-party ML)
        .target(name: "Domain", swiftSettings: strict),
        /// sqlite-vec v0.1.9 (vendored amalgamation), compiled against the system SQLite that GRDB uses.
        .target(name: "CSQLiteVec", cSettings: [.define("SQLITE_CORE")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(
            name: "Persistence",
            dependencies: ["Domain", "CSQLiteVec", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strict
        ),
        .target(
            name: "Config",
            dependencies: ["Domain", "Persistence", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Resources/Seeds")],
            swiftSettings: strict
        ),
        .target(
            name: "Pipeline",
            dependencies: [
                "Domain", "Persistence", "Config", .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: strict
        ),
        .target(name: "Search", dependencies: ["Domain", "Persistence", "Config"], swiftSettings: strict),
        .target(name: "Audio", dependencies: ["Domain"], swiftSettings: strict),
        .target(name: "Features", dependencies: ["Domain"], swiftSettings: ui),
        /// Apple system frameworks used as data sources (NaturalLanguage, Contacts).
        .target(name: "SystemServices", dependencies: ["Domain", "Persistence"], swiftSettings: strict),

        // MARK: Engines (the only targets that import ML SDKs)
        .target(
            name: "FluidAudioEngine",
            dependencies: ["Domain", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Engines/FluidAudioEngine",
            swiftSettings: strict
        ),

        .target(
            name: "SpeechAnalyzerEngine", dependencies: ["Domain"], path: "Sources/Engines/SpeechAnalyzerEngine",
            swiftSettings: strict),

        // MARK: Composition root
        .target(
            name: "AppComposition",
            dependencies: [
                "Domain", "Persistence", "Config", "Pipeline", "Search", "Audio", "Features", "SystemServices",
                "FluidAudioEngine", "SpeechAnalyzerEngine",
            ],
            swiftSettings: ui
        ),

        // MARK: Test support
        .target(
            name: "TestSupport",
            dependencies: [
                "Domain", "Persistence", "Config", "Features",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Clocks", package: "swift-clocks"),
            ],
            swiftSettings: strict
        ),

        // MARK: Fast tests (run on every change)
        .testTarget(name: "DomainTests", dependencies: ["Domain"], swiftSettings: strict),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "TestSupport", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strict
        ),
        .testTarget(
            name: "ConfigTests",
            dependencies: ["Config", "Persistence", "TestSupport", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strict
        ),
        .testTarget(
            name: "PipelineTests",
            dependencies: [
                "Pipeline", "Config", "Persistence", "TestSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Clocks", package: "swift-clocks"),
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "SearchTests", dependencies: ["Search", "Config", "Persistence", "Domain", "TestSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "FeaturesTests", dependencies: ["Features", "Domain", "TestSupport"], swiftSettings: ui),

        .testTarget(
            name: "AppCompositionTests",
            dependencies: ["AppComposition", "Config", "Domain", "Persistence", "TestSupport"],
            swiftSettings: ui),
        .testTarget(
            name: "SpeechAnalyzerEngineTests", dependencies: ["SpeechAnalyzerEngine", "Domain"], swiftSettings: strict),
        .testTarget(
            name: "SystemServicesTests", dependencies: ["SystemServices", "Domain"], swiftSettings: strict),
        .testTarget(
            name: "FluidAudioEngineTests", dependencies: ["FluidAudioEngine", "Domain"], swiftSettings: strict),

        // MARK: Integration tests (real models; skipped by scripts/check.sh)
        .testTarget(
            name: "SpeechAnalyzerEngineIntegrationTests", dependencies: ["SpeechAnalyzerEngine", "Domain"],
            resources: [.copy("Fixtures")], swiftSettings: strict),
        .testTarget(
            name: "FluidAudioEngineIntegrationTests",
            dependencies: ["FluidAudioEngine", "Domain"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
    ]
)
