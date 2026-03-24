// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ScreenTimeDataCleaner",
    platforms: [
        // These are the current minimum targets for these platforms but this code will silently not
        //  work unless iOS/macOS 26 is available.
        .iOS("15.0"),
        .macOS("11.4"),
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
