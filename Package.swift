// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "keepMacClear",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "keepMacClear",
            path: "Sources/keepMacClear",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-warnings-as-errors"]),
            ]
        )
    ]
)
