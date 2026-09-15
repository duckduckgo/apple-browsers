// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VPN",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(name: "VPN", targets: ["VPN"]),
        .library(name: "VPNTestUtils", targets: ["VPNTestUtils"]),
    ],
    dependencies: [
        .package(path: "../WideEvent"),
        .package(path: "../Common"),
        .package(path: "../Persistence"),
        .package(path: "../PixelKit"),
        .package(path: "../BrowserServicesKit"),
        .package(path: "../Infrastructure/SystemFrameworksExtensions"),
    ],
    targets: [
        .target(
            name: "VPN",
            dependencies: [
                .product(name: "WideEvent", package: "WideEvent"),
                .target(name: "WireGuardC"),
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Networking", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Subscription", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "PixelKit")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),

        .target(name: "WireGuardC"),

        .target(
            name: "VPNTestUtils",
            dependencies: [
                "VPN",
            ]
        ),

        .testTarget(
            name: "VPNTests",
            dependencies: [
                .product(name: "WideEvent", package: "WideEvent"),
                "VPN",
                "VPNTestUtils",
                .product(name: "NetworkingTestingUtils", package: "BrowserServicesKit"),
            ],
            resources: [
                .copy("Resources/servers-original-endpoint.json"),
                .copy("Resources/servers-updated-endpoint.json"),
                .copy("Resources/locations-endpoint.json")
            ]
        ),

    ]
)
