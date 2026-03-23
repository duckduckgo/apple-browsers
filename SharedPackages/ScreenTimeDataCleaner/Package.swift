// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ScreenTimeDataCleaner",
    platforms: [
        .iOS("15.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(
            name: "ScreenTimeDataCleaner",
            targets: ["ScreenTimeDataCleaner"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "ScreenTimeDataCleaner",
            dependencies: [
            ]
        ),
    ]
)
