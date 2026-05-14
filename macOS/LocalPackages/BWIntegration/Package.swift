// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BWIntegration",
    platforms: [
        .macOS("11.4")
    ],
    products: [
        .library(name: "BWIntegration", targets: ["BWIntegration"]),
        .library(name: "BWManagementShared", targets: ["BWManagementShared"]),
        .library(name: "BWManagement", targets: ["BWManagement"])
    ],
    dependencies: [
        .package(path: "../AppKitExtensions"),
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(url: "https://github.com/duckduckgo/OpenSSL-XCFramework", exact: "3.3.2000")
    ],
    targets: [
        .target(
            name: "BWIntegration",
            dependencies: [
                .product(name: "OpenSSL", package: "OpenSSL-XCFramework")
            ],
            path: "Sources/BWIntegration",
            sources: [
                "BWEncryption.m",
                "BWEncryptionOutput.m"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "BWManagementShared",
            dependencies: []
        ),
        .target(
            name: "BWManagement",
            dependencies: [
                "BWManagementShared",
                "BWIntegration",
                "AppKitExtensions",
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit")
            ]
        ),
        .testTarget(
            name: "BWManagementSharedTests",
            dependencies: [
                "BWManagementShared",
                .product(name: "Common", package: "BrowserServicesKit")
            ]
        ),
        .testTarget(
            name: "BWIntegrationTests",
            dependencies: [
                "BWIntegration",
                .product(name: "OpenSSL", package: "OpenSSL-XCFramework")
            ]
        )
    ]
)
