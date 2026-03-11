// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AutomationServer",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(name: "AutomationServer", targets: ["AutomationServer"])
    ],
    targets: [
        .target(
            name: "AutomationServer",
            dependencies: [],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "AutomationServerTests",
            dependencies: ["AutomationServer"]
        )
    ]
)
