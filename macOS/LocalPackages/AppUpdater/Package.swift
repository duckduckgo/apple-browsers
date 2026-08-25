// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppUpdater",
    platforms: [ .macOS("12.3") ],
    products: [
        .library(name: "AppUpdaterShared", targets: ["AppUpdaterShared"]),
        .library(name: "AppStoreAppUpdater", targets: ["AppStoreAppUpdater"]),
        .library(name: "SparkleAppUpdater", targets: ["SparkleAppUpdater"]),
        .library(name: "AppUpdaterTestHelpers", targets: ["AppUpdaterTestHelpers"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6"),
        .package(path: "../../../SharedPackages/DDGError"),
        .package(path: "../../../SharedPackages/Common"),
        .package(path: "../../../SharedPackages/Persistence"),
        .package(path: "../../../SharedPackages/PixelKit"),
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../../../SharedPackages/Infrastructure/SystemFrameworksExtensions"),
        .package(path: "../FeatureFlags-macOS"),
    ],
    targets: [
        .target(
            name: "AppUpdaterShared",
            dependencies: [
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "FeatureFlags-macOS", package: "FeatureFlags-macOS"),
                .product(name: "Navigation", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "PixelKit", package: "PixelKit"),
                .product(name: "Subscription", package: "BrowserServicesKit"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "AppStoreAppUpdater",
            dependencies: [
                .product(name: "DDGError", package: "DDGError"),
                "AppUpdaterShared",
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "FeatureFlags-macOS", package: "FeatureFlags-macOS"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "PixelKit", package: "PixelKit"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "SparkleAppUpdater",
            dependencies: [
                "AppUpdaterShared",
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "FeatureFlags-macOS", package: "FeatureFlags-macOS"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        // MARK: - Tests
        .target(
            name: "AppUpdaterTestHelpers",
            dependencies: [
                "AppUpdaterShared",
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "FeatureFlags-macOS", package: "FeatureFlags-macOS"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "PixelKit", package: "PixelKit"),
                .product(name: "PrivacyConfig", package: "BrowserServicesKit"),
            ],
            path: "Tests/AppUpdaterTestHelpers",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "AppUpdaterSharedTests",
            dependencies: [
                "AppUpdaterShared",
                "AppUpdaterTestHelpers",
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "Persistence", package: "Persistence"),
            ]
        ),
        .testTarget(
            name: "AppStoreAppUpdaterTests",
            dependencies: [
                "AppStoreAppUpdater",
                "AppUpdaterShared",
                "AppUpdaterTestHelpers",
                .product(name: "NetworkingTestingUtils", package: "BrowserServicesKit"),
                .product(name: "BrowserServicesKitTestsUtils", package: "BrowserServicesKit"),
            ]
        ),
        .testTarget(
            name: "SparkleAppUpdaterTests",
            dependencies: [
                "SparkleAppUpdater",
                "AppUpdaterShared",
                "AppUpdaterTestHelpers",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "BrowserServicesKitTestsUtils", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "PixelKit", package: "PixelKit"),
                .product(name: "PrivacyConfig", package: "BrowserServicesKit"),
            ]
        ),
    ]
)
