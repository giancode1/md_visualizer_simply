// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VisualizadorGC",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "VisualizadorGC", path: "Sources/VisualizadorGC")
    ]
)
