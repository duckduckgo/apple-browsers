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
        .package(path: "../BrowserServicesKit"),
        .package(path: "../Infrastructure/SystemFrameworksExtensions"),
        .package(path: "../AIChat")
    ],
    targets: [
        .target(
            name: "SERPSettings",
            dependencies: [
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
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
                .product(name: "BrowserServicesKitTestsUtils", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "AIChat", package: "AIChat")
            ]
        ),
    ]
)
