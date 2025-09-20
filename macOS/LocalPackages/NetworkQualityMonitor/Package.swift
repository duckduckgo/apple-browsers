// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NetworkQualityMonitor",
    platforms: [
        .macOS("11.4"),
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "NetworkQualityMonitor",
            targets: ["NetworkQualityMonitor"]
        )
    ],
    targets: [
        .target(
            name: "NetworkQualityMonitor",
            dependencies: []
        ),
        .testTarget(
            name: "NetworkQualityMonitorTests",
            dependencies: ["NetworkQualityMonitor"]
        )
    ]
)
