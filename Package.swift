// swift-tools-version:5.2
import PackageDescription

let packageName = "DuckDuckGo"
let package = Package(
    name: packageName,
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: packageName, targets: [packageName])
    ],
    dependencies: [
        // Add your dependencies here if needed
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [],
            path: "iOS/DuckDuckGo",
            exclude: ["Info.plist"] // Exclude any non-swift files
        ),
        .testTarget(
            name: "DuckDuckGoTests",
            dependencies: [.target(name: packageName)],
            path: "iOS/DuckDuckGoTests"
        )
    ]
)
