// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SERPSettings",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "SERPSettings",
            targets: ["SERPSettings"]
        ),
    ],
    dependencies: [
        .package(path: "../BrowserServicesKit"),
        .package(path: "../AIChat")
    ],
    targets: [
        .target(
            name: "SERPSettings",
            dependencies: [
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "AIChat", package: "AIChat")
            ]
        ),
        .testTarget(
            name: "SERPSettingsTests",
            dependencies: [
                "SERPSettings",
                .product(name: "Persistence", package: "BrowserServicesKit"),
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "AIChat", package: "AIChat")
            ]
        ),
    ]
)
