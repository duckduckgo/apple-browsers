// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SERPInstallOrigin",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(name: "SERPInstallOrigin", targets: ["SERPInstallOrigin"])
    ],
    dependencies: [
        .package(path: "../BrowserServicesKit")
    ],
    targets: [
        .target(
            name: "SERPInstallOrigin",
            dependencies: [
                .product(name: "UserScript", package: "BrowserServicesKit")
            ]
        ),
        .testTarget(
            name: "SERPInstallOriginTests",
            dependencies: [
                "SERPInstallOrigin",
                .product(name: "BrowserServicesKitTestsUtils", package: "BrowserServicesKit"),
                .product(name: "UserScript", package: "BrowserServicesKit")
            ]
        )
    ]
)
