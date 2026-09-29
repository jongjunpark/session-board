// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionBoard",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SessionBoard",
            path: "Sources/SessionBoard"
        ),
    ],
    swiftLanguageModes: [.v5]
)
