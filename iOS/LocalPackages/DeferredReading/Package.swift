// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DeferredReading",
    defaultLocalization: "en",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(
            name: "DeferredReadingCore",
            targets: ["DeferredReadingCore"]
        ),
        .library(
            name: "DeferredReadingUI",
            targets: ["DeferredReadingUI"]
        ),
        .library(
            name: "DeferredReadingTestSupport",
            targets: ["DeferredReadingTestSupport"]
        )
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKit"),
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKitIcons")
    ],
    targets: [
        .target(
            name: "DeferredReadingCore",
            dependencies: [
                .product(name: "Persistence", package: "BrowserServicesKit")
            ]
        ),
        .target(
            name: "DeferredReadingUI",
            dependencies: [
                "DeferredReadingCore",
                .product(name: "DesignResourcesKit", package: "DesignResourcesKit"),
                .product(name: "DesignResourcesKitIcons", package: "DesignResourcesKitIcons")
            ]
        ),
        .target(
            name: "DeferredReadingTestSupport",
            dependencies: [
                "DeferredReadingCore",
                .product(name: "Persistence", package: "BrowserServicesKit")
            ]
        ),
        .testTarget(
            name: "DeferredReadingTests",
            dependencies: [
                "DeferredReadingCore",
                "DeferredReadingTestSupport"
            ]
        )
    ]
)
