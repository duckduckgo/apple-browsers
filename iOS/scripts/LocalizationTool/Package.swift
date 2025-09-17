// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LocalizationTool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "localization-tool", targets: ["LocalizationTool"]) 
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SmartlingAPIClient",
            dependencies: [],
            path: "Sources/SmartlingAPIClient"
        ),
        .executableTarget(
            name: "LocalizationTool",
            dependencies: [
                "SmartlingAPIClient",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/LocalizationTool"
        )
    ]
)


