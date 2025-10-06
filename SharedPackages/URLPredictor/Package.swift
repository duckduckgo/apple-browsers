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
            url: "https://github.com/duckduckgo/url_predictor/releases/download/0.3.1/URLPredictorRust.xcframework.zip",
            checksum: "0ea6ba050b3b02cfe3dfbeb268e6740675168fe6773cd3a631c4e37945cb7da2"
        ),
        .testTarget(name: "URLPredictorTests", dependencies: ["URLPredictor"])
    ]
)
