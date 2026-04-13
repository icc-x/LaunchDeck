// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LaunchDeck",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "LaunchDeck", targets: ["LaunchDeck"])
    ],
    targets: [
        .executableTarget(
            name: "LaunchDeck",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LaunchDeckTests",
            dependencies: [
                "LaunchDeck",
            ],
            path: "Tests/LaunchDeckTests"
        ),
    ]
)
