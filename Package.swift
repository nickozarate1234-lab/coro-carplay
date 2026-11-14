// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LyricsCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LyricsCore", targets: ["LyricsCore"])],
    targets: [
        .target(name: "LyricsCore"),
        .testTarget(name: "LyricsCoreTests", dependencies: ["LyricsCore"])
    ]
)
