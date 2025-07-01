// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Waitlist",
    platforms: [
        .iOS(.v15)
    ],

    products: [
        .library(
            name: "Waitlist",
            targets: ["Waitlist", "WaitlistMocks"])
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/DesignResourcesKit", exact: "5.0.0"),
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", revision: "e7814e0aab72c941d5780b2a9f66bc621fde426c"),
    ],
    targets: [
        .target(
            name: "Waitlist",
            dependencies: [
                "DesignResourcesKit",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "WaitlistMocks",
            dependencies: ["Waitlist"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "WaitlistTests",
            dependencies: ["Waitlist", "WaitlistMocks"]
        )
    ]
)
