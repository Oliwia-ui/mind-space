// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MindSpace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MindSpaceCore", targets: ["MindSpaceCore"]),
        .executable(name: "MindSpace", targets: ["MindSpaceApp"]),
    ],
    targets: [
        .target(
            name: "MindSpaceCore",
            path: "Sources/MindSpaceCore"
        ),
        .executableTarget(
            name: "MindSpaceApp",
            dependencies: ["MindSpaceCore"],
            path: "Sources/MindSpaceApp"
        ),
        .testTarget(
            name: "MindSpaceCoreTests",
            dependencies: ["MindSpaceCore"],
            path: "Tests/MindSpaceCoreTests"
        ),
    ]
)
