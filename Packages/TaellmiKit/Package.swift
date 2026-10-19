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
    defaultLocalization: "de",
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
        .target(
            name: "Persistence",
            dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")],
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
        .target(name: "Audio", dependencies: ["Domain"], swiftSettings: strict),
        .target(name: "Features", dependencies: ["Domain"], swiftSettings: ui),
        /// Apple system frameworks used as data sources (NaturalLanguage, Contacts).
        .target(name: "SystemServices", dependencies: ["Domain"], swiftSettings: strict),

        // MARK: Engines (the only targets that import ML SDKs)
        .target(
            name: "FluidAudioEngine",
            dependencies: ["Domain", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Engines/FluidAudioEngine",
            swiftSettings: strict
        ),

        // MARK: Composition root
        .target(
            name: "AppComposition",
            dependencies: [
                "Domain", "Persistence", "Config", "Pipeline", "Audio", "Features", "SystemServices",
                "FluidAudioEngine",
            ],
            swiftSettings: ui
        ),

        // MARK: Test support
        .target(
            name: "TestSupport",
            dependencies: [
                "Domain", "Persistence", "Config",
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
            name: "FeaturesTests", dependencies: ["Features", "TestSupport"], swiftSettings: ui),

        .testTarget(
            name: "AppCompositionTests",
            dependencies: ["AppComposition", "Config", "Domain", "Persistence", "TestSupport"],
            swiftSettings: ui),
        .testTarget(name: "SystemServicesTests", dependencies: ["SystemServices", "Domain"], swiftSettings: strict),
        .testTarget(
            name: "FluidAudioEngineTests", dependencies: ["FluidAudioEngine", "Domain"], swiftSettings: strict),

        // MARK: Integration tests (real models; skipped by scripts/check.sh)
        .testTarget(
            name: "FluidAudioEngineIntegrationTests",
            dependencies: ["FluidAudioEngine", "Domain"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
    ]
)
