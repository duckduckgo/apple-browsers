// swift-tools-version: 6.1
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
        .package(path: "../../../SharedPackages/DesignResourcesKitIcons"),
        .package(path: "../MetricBuilder"),
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", exact: "3.2.1"),
    ],
    targets: [
        .target(
            name: "SetDefaultBrowserCore"
        ),
        .target(
            name: "SetDefaultBrowserUI",
            dependencies: [
                .product(name: "DuckUI", package: "DuckUI"),
                .product(name: "MetricBuilder", package: "MetricBuilder"),
                .product(name: "DesignResourcesKitIcons", package: "DesignResourcesKitIcons"),
            ]
        ),
        .target(
            name: "SetDefaultBrowserTestSupport",
            dependencies: [
                "SetDefaultBrowserCore"
            ]
        ),
        .testTarget(
            name: "SetDefaultBrowserTests",
            dependencies: [
                "SetDefaultBrowserCore",
                "SetDefaultBrowserTestSupport",
            ]
        ),
    ]
)
