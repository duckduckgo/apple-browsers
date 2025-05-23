// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DesignResourcesKitIcons",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "DesignResourcesKitIcons",
            targets: ["DesignResourcesKitIcons"]),
    ],
    targets: [
        .target(
            name: "DesignResourcesKitIcons",
            resources: [
                .process("DesignSystemImages.xcassets")
            ]
        ),

    ]
)
