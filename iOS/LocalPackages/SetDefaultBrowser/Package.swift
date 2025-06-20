// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SetDefaultBrowser",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(
            name: "SetDefaultBrowserCore",
            targets: ["SetDefaultBrowserCore"]
        ),
        .library(
            name: "SetDefaultBrowserTestSupport",
            targets: ["SetDefaultBrowserTestSupport"]
        ),
    ],
    targets: [
        .target(
            name: "SetDefaultBrowserCore"
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
