// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReaderMode",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "ReaderMode", targets: ["ReaderMode"])],
    dependencies: [
        .package(path: "ThirdParty/Trafilatura"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9")
    ],
    targets: [
        .target(name: "ReaderMode", dependencies: [
            .product(name: "Trafilatura", package: "Trafilatura"),
            .product(name: "SwiftSoup", package: "SwiftSoup")
        ]),
        .testTarget(name: "ReaderModeTests", dependencies: ["ReaderMode", "SwiftSoup"], resources: [.copy("Fixtures")])
    ]
)
