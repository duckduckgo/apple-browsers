// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppKitExtensions",
    platforms: [ .macOS("12.3") ],
    products: [
        .library(name: "AppKitExtensions", targets: ["AppKitExtensions"]),
    ],
    dependencies: [
        .package(path: "../Utilities"),
        .package(path: "../../../SharedPackages/Common"),
        .package(path: "../../../SharedPackages/Infrastructure/SystemFrameworksExtensions"),
    ],
    targets: [
        .target(
            name: "AppKitExtensions",
            dependencies: [
                "Utilities",
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "AppKitExtensionsTests",
            dependencies: [
                "AppKitExtensions"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
