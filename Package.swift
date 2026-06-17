// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotatyAppstore",
    platforms: [.macOS(.v13)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NotatyAppstore",
            dependencies: [],
            path: "Sources/Notaty",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Sources/Notaty/Info.plist"]),
            ]
        )
    ]
)
