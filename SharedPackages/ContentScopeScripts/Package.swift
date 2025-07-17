// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContentScopeScripts",
    products: [
        .library(
            name: "ContentScopeScripts",
            targets: ["ContentScopeScripts"]
        ),
    ],
    targets: [
        .target(
            name: "ContentScopeScripts",
            dependencies: [],
            resources: [
                .process("Resources/contentScope.js"),
                .process("Resources/contentScopeIsolated.js"),
                .copy("Resources/pages"),
            ]
        ),
    ]
)
