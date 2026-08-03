// swift-tools-version: 6.3

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
            ]
        ),
        .testTarget(
            name: "BonsplitTests",
            dependencies: ["Bonsplit"],
            path: "Tests/BonsplitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
