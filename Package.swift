// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PollenCodexPets",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "render-pets", path: "Sources/RenderPets"),
    ]
)
