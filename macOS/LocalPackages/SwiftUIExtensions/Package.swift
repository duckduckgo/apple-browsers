// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftUIExtensions",
    platforms: [ .macOS("11.4") ],
    products: [
        .library(name: "SwiftUIExtensions", targets: ["SwiftUIExtensions"]),
    ],
    dependencies: [
        .package(path: "../Infrastructure/DesignResourcesKit")
    ],
    targets: [
        .target(
            name: "SwiftUIExtensions",
            dependencies: [
                "DesignResourcesKit"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
    ]
)
