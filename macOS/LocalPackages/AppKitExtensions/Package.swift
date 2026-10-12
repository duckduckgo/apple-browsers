// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Xcode maps the app's CI configuration to release for Swift packages. The macOS CI workflows
// set this flag so ApplicationBuildType sees the same DEBUG condition as the app target.
let forceDebug = ProcessInfo.processInfo.environment["SPM_FORCE_DEBUG"] == "1"

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
            ] + (forceDebug ? [.define("DEBUG")] : [])
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
