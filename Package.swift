// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "utility-suite",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "WebPDropCore",
            targets: ["WebPDropCore"]
        ),
        .executable(
            name: "WebPDrop",
            targets: ["WebPDrop"]
        ),
    ],
    targets: [
        .target(
            name: "WebPDropCore"
        ),
        .executableTarget(
            name: "WebPDrop",
            dependencies: ["WebPDropCore"]
        ),
        .testTarget(
            name: "WebPDropCoreTests",
            dependencies: ["WebPDropCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
