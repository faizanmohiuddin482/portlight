// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Portlight",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PortlightCore"),
        .executableTarget(name: "Portlight", dependencies: ["PortlightCore"]),
        .testTarget(
            name: "PortlightCoreTests",
            dependencies: ["PortlightCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PortlightTests", dependencies: ["Portlight", "PortlightCore"]),
    ]
)
