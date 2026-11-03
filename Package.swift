// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "agy-usage-stats",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(
            name: "agy-usage-stats",
            targets: ["agy-usage-stats"]
        )
    ],
    targets: [
        .executableTarget(
            name: "agy-usage-stats",
            path: "agy-usage-stats",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "agy-usage-statsTests",
            dependencies: ["agy-usage-stats"],
            path: "agy-usage-statsTests"
        )
    ]
)
