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
        .library(name: "URLPredictor", targets: ["URLPredictor", "URLPredictorC"]),
    ],
    targets: [
        .target(name: "URLPredictor", dependencies: ["URLPredictorC"]),
        .binaryTarget(
            name: "URLPredictorC",
            path: "URLPredictorC.xcframework"
        ),
        .testTarget(name: "URLPredictorTests", dependencies: ["URLPredictor"])
    ]
)
