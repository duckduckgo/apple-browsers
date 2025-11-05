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
            url: "https://github.com/duckduckgo/url_predictor/releases/download/0.3.2/URLPredictorRust.xcframework.zip",
            checksum: "17bcf2dc9829e0ee5e36eaae9729b866d0a7d1df387c219a5a01234540dd31cc"
        ),
        .testTarget(name: "URLPredictorTests", dependencies: ["URLPredictor"])
    ]
)
