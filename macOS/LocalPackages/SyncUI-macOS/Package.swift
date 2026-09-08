// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Set by the "Build for testing" step in .github/workflows/macos_pr_checks.yml. Under CI the package builds
// in release configuration (SPM maps the CI configuration to .release), so `.when(configuration: .debug)` below
// doesn't fire and the DEBUG-only snapshot tests wouldn't compile. This forces DEBUG on for that CI build.
let forceDebugForSnapshots = ProcessInfo.processInfo.environment["SPM_FORCE_DEBUG_FOR_SNAPSHOTS"] == "1"

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
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKitIcons"),
        .package(path: "../../../SharedPackages/SnapshotTestingSupport"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", exact: "4.6.1"),
    ],
    targets: [
        .target(
            name: "SyncUI-macOS",
            dependencies: [
                .product(name: "PreferencesUI-macOS", package: "PreferencesUI-macOS"),
                .product(name: "SwiftUIExtensions", package: "SwiftUIExtensions"),
                .product(name: "DesignResourcesKit", package: "DesignResourcesKit"),
                .product(name: "DesignResourcesKitIcons", package: "DesignResourcesKitIcons"),
                .product(name: "PreviewSnapshots", package: "SnapshotTestingSupport"),
                .product(name: "Lottie", package: "lottie-spm"),
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ] + (forceDebugForSnapshots ? [.define("DEBUG")] : [])
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
