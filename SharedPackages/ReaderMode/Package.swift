// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReaderMode",
    platforms: [.iOS(.v15), .macOS("12.3")],
    products: [.library(name: "ReaderMode", targets: ["ReaderMode"])],
    dependencies: [
        .package(path: "../Infrastructure/DesignResourcesKit"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9")
    ],
    targets: [
        .target(name: "ReaderMode", dependencies: [
            "Trafilatura",
            .product(name: "DesignResourcesKit", package: "DesignResourcesKit"),
            .product(name: "SwiftSoup", package: "SwiftSoup")
        ]),
        // Upstream trafilatura-swift ships a static library, which clashes with the macOS app's other Rust static library.
        // The fork builds a dynamic framework. The bindings must come from the same release as the binary.
        .binaryTarget(
            name: "TrafilaturaFFI",
            url: "https://github.com/ayoy/trafilatura-rs/releases/download/v0.5.0-ddg.1/TrafilaturaFFI.xcframework.zip",
            checksum: "5c7d747e8132229d09c7e447cfe42e756d4717e3408dd304706b745b59cef625"
        ),
        .target(
            name: "Trafilatura",
            dependencies: ["TrafilaturaFFI"],
            linkerSettings: [.linkedFramework("CoreFoundation")]
        ),
        .testTarget(name: "ReaderModeTests", dependencies: ["ReaderMode", "SwiftSoup"], resources: [.copy("Fixtures")])
    ]
)
