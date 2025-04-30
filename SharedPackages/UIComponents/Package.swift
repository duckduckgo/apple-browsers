// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UIComponents",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "UIComponents",
            targets: ["UIComponents"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/DesignResourcesKit", exact: "4.2.0")
    ],
    targets: [
        .target(
            name: "UIComponents",
            dependencies: [
                "DesignResourcesKit",
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "UIComponentsTests",
            dependencies: ["UIComponents"]
        ),
    ]
)
