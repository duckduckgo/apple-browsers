// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "URLPredictor",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
    ],
    products: [
        .library(name: "URLPredictor", targets: ["URLPredictor"]),
    ],
    targets: [
        .target(name: "URLPredictor", dependencies: ["URLPredictorRust"]),
        .binaryTarget(
            name: "URLPredictorRust",
            url: "https://github.com/duckduckgo/url_predictor/releases/download/0.1.0/URLPredictorRust.xcframework.zip",
            checksum: "b69df3adb2fbf4e2c07123535434e6f3ae91c8581c7592ab88e0c0640e4d2b2e"
        ),
        .testTarget(name: "URLPredictorTests", dependencies: ["URLPredictor"])
    ]
)
