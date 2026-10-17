// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LoginItems",
    platforms: [ .macOS("12.3") ],
    products: [
        .library(
            name: "LoginItems",
            targets: ["LoginItems"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "LoginItems",
            dependencies: [
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
    ]
)
