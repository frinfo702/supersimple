// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SupersimpleCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SupersimpleCore", targets: ["SupersimpleCore"]),
    ],
    targets: [
        .target(
            name: "SupersimpleCore"
        ),
        .testTarget(
            name: "SupersimpleCoreTests",
            dependencies: ["SupersimpleCore"]
        ),
    ]
)