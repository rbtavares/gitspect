// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GitSpect",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GitSpect", path: "Sources/GitSpect")
    ]
)
