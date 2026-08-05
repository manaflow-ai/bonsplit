// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Bonsplit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Bonsplit",
            targets: ["Bonsplit"]
        ),
    ],
    targets: [
        .target(
            name: "Bonsplit",
            dependencies: [],
            path: "Sources/Bonsplit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "BonsplitTests",
            dependencies: ["Bonsplit"],
            path: "Tests/BonsplitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
