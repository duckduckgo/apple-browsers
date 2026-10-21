// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Trafilatura",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "Trafilatura", targets: ["Trafilatura"])],
    targets: [
        .binaryTarget(name: "TrafilaturaFFI", path: "Vendor/TrafilaturaFFI.xcframework"),
        .target(
            name: "Trafilatura",
            dependencies: ["TrafilaturaFFI"],
            linkerSettings: [.linkedFramework("CoreFoundation")]
        )
    ]
)
