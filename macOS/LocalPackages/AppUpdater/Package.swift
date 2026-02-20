// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppUpdater",
    platforms: [ .macOS("11.4") ],
    products: [
        .library(name: "AppUpdaterShared", targets: ["AppUpdaterShared"]),
        .library(name: "AppStoreAppUpdater", targets: ["AppStoreAppUpdater"]),
        .library(name: "SparkleAppUpdater", targets: ["SparkleAppUpdater"]),
        .library(name: "AppUpdaterTestHelpers", targets: ["AppUpdaterTestHelpers"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.8.1"),
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../FeatureFlags"),
    ],
    targets: [
        .target(
            name: "AppUpdaterShared",
            dependencies: [
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "FeatureFlags", package: "FeatureFlags"),
                .product(name: "Navigation", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit"),
                .product(name: "Subscription", package: "BrowserServicesKit"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "AppStoreAppUpdater",
            dependencies: [
                "AppUpdaterShared",
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "FeatureFlags", package: "FeatureFlags"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit"),
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
                .product(name: "FeatureFlags", package: "FeatureFlags"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
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
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "FeatureFlags", package: "FeatureFlags"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit"),
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
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit"),
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
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit"),
                .product(name: "PixelKitTestingUtilities", package: "BrowserServicesKit"),
                .product(name: "PrivacyConfig", package: "BrowserServicesKit"),
            ]
        ),
    ]
)
