// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhosttyEmbed",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GhosttyEmbed", targets: ["GhosttyEmbed"])
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "GhosttyKit.xcframework"
        ),
        .target(
            name: "GhosttyEmbed",
            dependencies: ["GhosttyKit"],
            path: "Sources/GhosttyEmbed",
            swiftSettings: [
                // Disable strict concurrency to match Ghostty's assumptions
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
