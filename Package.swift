// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NotchTune",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "NotchTuneCore",
            targets: ["NotchTuneCore"]
        ),
        .executable(
            name: "NotchTuneHooks",
            targets: ["NotchTuneHooks"]
        ),
        .executable(
            name: "NotchTuneSetup",
            targets: ["NotchTuneSetup"]
        ),
        .executable(
            name: "NotchTuneApp",
            targets: ["NotchTuneApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        .target(
            name: "NotchTuneCore"
        ),
        .executableTarget(
            name: "NotchTuneHooks",
            dependencies: ["NotchTuneCore"]
        ),
        .executableTarget(
            name: "NotchTuneSetup",
            dependencies: ["NotchTuneCore"]
        ),
        .executableTarget(
            name: "NotchTuneApp",
            dependencies: [
                "NotchTuneCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "NotchTuneCoreTests",
            dependencies: ["NotchTuneCore"]
        ),
        .testTarget(
            name: "NotchTuneAppTests",
            dependencies: ["NotchTuneApp", "NotchTuneCore"]
        ),
    ]
)
