// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VPN",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(name: "VPN", targets: ["VPN"]),
        .library(name: "VPNTestUtils", targets: ["VPNTestUtils"]),
    ],
    dependencies: [
        .package(path: "../BrowserServicesKit"),
    ],
    targets: [
        .target(
            name: "VPN",
            dependencies: [
                .target(name: "WireGuardC"),
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "Networking", package: "BrowserServicesKit"),
                .product(name: "Subscription", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit")
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
