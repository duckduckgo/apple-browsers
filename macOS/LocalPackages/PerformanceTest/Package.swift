// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PerformanceTest",
    platforms: [
        .macOS("11.4") // Match NetworkQualityMonitor requirement
    ],
    products: [
        .library(
            name: "PerformanceTest",
            targets: ["PerformanceTest"]),
    ],
    dependencies: [
        // Add NetworkQualityMonitor dependency
        .package(path: "../NetworkQualityMonitor"),
    ],
    targets: [
        .target(
            name: "PerformanceTest",
            dependencies: ["NetworkQualityMonitor"]),
    ]
)
