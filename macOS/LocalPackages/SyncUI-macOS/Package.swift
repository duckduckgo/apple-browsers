// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SyncUI-macOS",
    defaultLocalization: "en",
    platforms: [ .macOS("12.3") ],
    products: [
        .library(
            name: "SyncUI-macOS",
            targets: ["SyncUI-macOS"]),
    ],
    dependencies: [
        .package(path: "../PreferencesUI-macOS"),
        .package(path: "../SwiftUIExtensions"),
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKit"),
        .package(path: "../../../SharedPackages/SnapshotTestingSupport"),
    ],
    targets: [
        .target(
            name: "SyncUI-macOS",
            dependencies: [
                .product(name: "PreferencesUI-macOS", package: "PreferencesUI-macOS"),
                .product(name: "SwiftUIExtensions", package: "SwiftUIExtensions"),
                .product(name: "DesignResourcesKit", package: "DesignResourcesKit"),
                .product(name: "PreviewSnapshots", package: "SnapshotTestingSupport"),
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "SyncUI-macOSTests",
            dependencies: [
                "SyncUI-macOS",
                .product(name: "SnapshotTestingSupport", package: "SnapshotTestingSupport"),
            ]
        ),
    ]
)
