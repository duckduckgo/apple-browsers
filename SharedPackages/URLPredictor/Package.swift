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
            url: "https://github.com/duckduckgo/url_predictor/releases/download/0.2.4/URLPredictorRust.xcframework.zip",
            checksum: "3dfaa0c6dbba4d694ef16efb7a089ce00520385a8c8db3cfb3b81a2d265f898f"
        ),
        .testTarget(name: "URLPredictorTests", dependencies: ["URLPredictor"])
    ]
)
