// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Waitlist",
    platforms: [ .macOS("11.4") ],
    products: [
        .library(name: "Waitlist", targets: ["Waitlist"]),
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../SwiftUIExtensions"),
    ],
    targets: [
        .target(
            name: "Waitlist",
            dependencies: [
                .product(name: "Networking", package: "BrowserServicesKit"),
                .product(name: "SwiftUIExtensions", package: "SwiftUIExtensions"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
    ]
)
