// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Notaty",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Notaty",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Notaty"
        )
    ]
)
