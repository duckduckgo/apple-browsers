// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SetDefaultBrowser",
    defaultLocalization: "en",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(
            name: "SetDefaultBrowserCore",
            targets: ["SetDefaultBrowserCore"]
        ),
        .library(
            name: "SetDefaultBrowserUI",
            targets: ["SetDefaultBrowserUI"]
        ),
        .library(
            name: "SetDefaultBrowserTestSupport",
            targets: ["SetDefaultBrowserTestSupport"]
        ),
    ],
    dependencies: [
        .package(path: "../DuckUI"),
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKitIcons"),
        .package(path: "../../../SharedPackages/UIComponents"),
        .package(path: "../../../SharedPackages/Infrastructure/MetricBuilder"),
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", exact: "3.2.1"),
    ],
    targets: [
        .target(
            name: "SetDefaultBrowserCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "SetDefaultBrowserUI",
            dependencies: [
                "SetDefaultBrowserCore",
                .product(name: "DuckUI", package: "DuckUI"),
                .product(name: "MetricBuilder", package: "MetricBuilder"),
                .product(name: "DesignResourcesKitIcons", package: "DesignResourcesKitIcons"),
                .product(name: "UIComponents", package: "UIComponents"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "SetDefaultBrowserTestSupport",
            dependencies: [
                "SetDefaultBrowserCore"
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "SetDefaultBrowserTests",
            dependencies: [
                "SetDefaultBrowserCore",
                "SetDefaultBrowserTestSupport",
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
