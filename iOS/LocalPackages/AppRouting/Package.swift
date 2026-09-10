// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppRouting",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "AppRouting",
            targets: ["AppRouting"]
        )
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/Common"),
        .package(path: "../../../SharedPackages/Infrastructure/SystemFrameworksExtensions")
    ],
    targets: [
        .target(
            name: "AppRouting",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions")
            ]
        ),
        .testTarget(
            name: "AppRoutingTests",
            dependencies: [
                "AppRouting"
            ]
        )
    ]
)
