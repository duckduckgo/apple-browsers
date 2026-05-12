// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AddressBarPerformance",
    platforms: [
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "AddressBarPerformance",
            targets: ["AddressBarPerformance"]
        )
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/BrowserServicesKit")
    ],
    targets: [
        .target(
            name: "AddressBarPerformance",
            dependencies: [
                .product(name: "PixelKit", package: "BrowserServicesKit")
            ]
        ),
        .testTarget(
            name: "AddressBarPerformanceTests",
            dependencies: [
                "AddressBarPerformance",
                .product(name: "PixelKit", package: "BrowserServicesKit")
            ]
        )
    ]
)
