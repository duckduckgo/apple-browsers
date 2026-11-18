// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DuckWireGuard",
    platforms: [.iOS("15.0"), .macOS("12.3")],
    products: [
        .library(name: "DuckWireGuard", targets: ["DuckWireGuard"]),
        .executable(name: "duck-wireguard-probe", targets: ["DuckWireGuardProbe"])
    ],
    targets: [
        .target(name: "DuckWireGuard"),
        .executableTarget(name: "DuckWireGuardProbe", dependencies: ["DuckWireGuard"]),
        .testTarget(
            name: "DuckWireGuardTests",
            dependencies: ["DuckWireGuard"],
            resources: [.copy("Fixtures")]
        )
    ]
)
