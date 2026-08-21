// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InstallStatistics",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "InstallStatistics",
            targets: ["InstallStatistics"]
        )
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/Infrastructure/SystemFrameworksExtensions")
    ],
    targets: [
        .target(
            name: "InstallStatistics",
            dependencies: [
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions")
            ]
        ),
        .testTarget(
            name: "InstallStatisticsTests",
            dependencies: [
                "InstallStatistics"
            ]
        )
    ]
)
