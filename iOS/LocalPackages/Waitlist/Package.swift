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
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", revision: "56e1a23b1cb76f0b0ef4199fe7aa4c1f19bf21ff"),
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
