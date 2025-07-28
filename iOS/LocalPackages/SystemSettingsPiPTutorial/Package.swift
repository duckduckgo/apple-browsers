// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SystemSettingsPiPTutorial",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SystemSettingsPiPTutorial",
            targets: ["SystemSettingsPiPTutorial"]
        ),
        .library(
            name: "SystemSettingsPiPTutorialTestSupport",
            targets: ["SystemSettingsPiPTutorialTestSupport"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SystemSettingsPiPTutorial"
        ),
        .testTarget(
            name: "SystemSettingsPiPTutorialTests",
            dependencies: [
                "SystemSettingsPiPTutorial",
                "SystemSettingsPiPTutorialTestSupport"
            ]
        ),
        .target(
            name: "SystemSettingsPiPTutorialTestSupport",
            dependencies: [
                "SystemSettingsPiPTutorial"
            ],
            path: "Sources/SystemSettingsPiPTutorialTestSupport"
        ),
    ]
)
