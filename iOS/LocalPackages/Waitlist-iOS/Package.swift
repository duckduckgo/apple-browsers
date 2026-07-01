// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Waitlist-iOS",
    platforms: [
        .iOS(.v15)
    ],

    products: [
        .library(
            name: "Waitlist-iOS",
            targets: ["Waitlist-iOS", "WaitlistMocks"])
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKit"),
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", exact: "3.2.1"),
    ],
    targets: [
        .target(
            name: "Waitlist-iOS",
            dependencies: [
                "DesignResourcesKit",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "WaitlistMocks",
            dependencies: ["Waitlist-iOS"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "WaitlistTests",
            dependencies: ["Waitlist-iOS", "WaitlistMocks"]
        )
    ]
)
