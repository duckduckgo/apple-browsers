// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PerformanceTest",
    platforms: [
        .macOS("12.3") // Match NetworkQualityMonitor requirement
    ],
    products: [
        .library(
            name: "PerformanceTest",
            targets: ["PerformanceTest"])
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/Infrastructure/AssetCatalogPlugin"),
        // Add NetworkQualityMonitor dependency
        .package(path: "../NetworkQualityMonitor")
    ],
    targets: [
        .target(
            name: "PerformanceTest",
            dependencies: ["NetworkQualityMonitor"],
            resources: [
                .process("Resources"),
                .copy("SafariTestRunner")
            ],
            plugins: [
                // Compiles asset catalogs for `swift build`; Xcode does it itself
                .plugin(name: "AssetCatalogPlugin", package: "AssetCatalogPlugin")
            ]),
        .testTarget(
            name: "PerformanceTestTests",
            dependencies: ["PerformanceTest"])
    ]
)
