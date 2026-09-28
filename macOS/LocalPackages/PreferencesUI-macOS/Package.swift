// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PreferencesUI-macOS",
    defaultLocalization: "en",
    platforms: [ .macOS("12.3") ],
    products: [
        .library(name: "PreferencesUI-macOS", targets: ["PreferencesUI-macOS"]),
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/Infrastructure/AssetCatalogPlugin"),
        .package(path: "../SwiftUIExtensions"),
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKit")
    ],
    targets: [
        .target(
            name: "PreferencesUI-macOS",
            dependencies: [
                .product(name: "SwiftUIExtensions", package: "SwiftUIExtensions"),
                "DesignResourcesKit"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [
                // Compiles asset catalogs for `swift build`; Xcode does it itself
                .plugin(name: "AssetCatalogPlugin", package: "AssetCatalogPlugin")
            ]
        ),
    ]
)
