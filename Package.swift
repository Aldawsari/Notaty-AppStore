// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Notaty",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Notaty",
            path: "Sources/Notaty"
        )
    ]
)
