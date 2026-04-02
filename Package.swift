// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "keepMacClear",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "keepMacClear",
            path: "Sources/keepMacClear"
        )
    ]
)
