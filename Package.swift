// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BusyLight",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BusyLight",
            path: "Sources/BusyLight",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
