// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Standalone package, deliberately NOT referenced from DuckDuckGo.xcworkspace.
// It is a client of the in-app AutomationServer (SharedPackages/AutomationServer), so the
// MCP SDK and its transitive dependencies never enter the app targets or the workspace's Package.resolved.
let package = Package(
    name: "BrowserMCP",
    platforms: [
        .macOS("13.0")
    ],
    products: [
        .executable(name: "ddg-browser-mcp", targets: ["BrowserMCPTool"]),
        .library(name: "BrowserMCPTools", targets: ["BrowserMCPTools"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
    ],
    targets: [
        .target(
            name: "BrowserMCPTools",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .executableTarget(
            name: "BrowserMCPTool",
            dependencies: ["BrowserMCPTools"]
        ),
        .testTarget(
            name: "BrowserMCPToolsTests",
            dependencies: ["BrowserMCPTools"]
        )
    ]
)
