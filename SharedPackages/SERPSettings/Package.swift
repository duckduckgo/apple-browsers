// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SERPSettings",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(
            name: "SERPSettings",
            targets: ["SERPSettings"]
        ),
    ],
    dependencies: [
        .package(path: "../Common"),
        .package(path: "../Persistence"),
        .package(path: "../PixelKit"),
        .package(path: "../BrowserServicesKit"),
        .package(path: "../Infrastructure/SystemFrameworksExtensions"),
        .package(path: "../AIChat")
    ],
    targets: [
        .target(
            name: "SERPSettings",
            dependencies: [
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "PixelKit", package: "PixelKit"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "AIChat", package: "AIChat")
            ]
        ),
        .testTarget(
            name: "SERPSettingsTests",
            dependencies: [
                "SERPSettings",
                .product(name: "BrowserServicesKitTestsUtils", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "AIChat", package: "AIChat")
            ]
        ),
    ]
)
