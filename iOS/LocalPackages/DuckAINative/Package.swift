// swift-tools-version: 6.0

import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "DuckAINative",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DuckAINative", targets: ["DuckAINative", "DuckAIChatUI", "DuckAIChatCore", "DuckAIChatProviders",
                                                 "DuckAILocalTasks", "DuckAIEvals"]),
        .library(name: "DuckAIChatMLX", targets: ["DuckAIChatMLX"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        // 1.3.0 and later use Span, which below iOS 26 needs libswiftCompatibilitySpan.dylib and breaks archive export.
        .package(url: "https://github.com/apple/swift-collections", exact: "1.2.1")
    ],
    targets: [
        .target(name: "DuckAIChatCore", swiftSettings: v5),
        .target(name: "DuckAIChatProviders", dependencies: ["DuckAIChatCore"], swiftSettings: v5),
        .target(
            name: "DuckAIChatMLX",
            dependencies: [
                "DuckAIChatCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            swiftSettings: v5
        ),
        .target(name: "DuckAIChatUI", dependencies: ["DuckAIChatCore"], swiftSettings: v5),
        .target(name: "DuckAILocalTasks", dependencies: ["DuckAIChatCore"], swiftSettings: v5),
        .target(name: "DuckAIEvals", dependencies: ["DuckAIChatCore", "DuckAILocalTasks"], swiftSettings: v5),
        .target(name: "DuckAINative", dependencies: ["DuckAIChatCore", "DuckAIChatUI", "DuckAIChatProviders"], swiftSettings: v5),
        .testTarget(name: "DuckAIChatCoreTests", dependencies: ["DuckAIChatCore"], swiftSettings: v5),
        .testTarget(name: "DuckAIChatProvidersTests", dependencies: ["DuckAIChatCore", "DuckAIChatProviders"], swiftSettings: v5),
        .testTarget(name: "DuckAIChatUITests", dependencies: ["DuckAIChatUI"], swiftSettings: v5),
        .testTarget(name: "DuckAILocalTasksTests", dependencies: ["DuckAIChatCore", "DuckAIChatProviders", "DuckAILocalTasks"], swiftSettings: v5),
        .testTarget(name: "DuckAINativeTests", dependencies: ["DuckAINative"], swiftSettings: v5),
        .testTarget(name: "DuckAIEvalsTests", dependencies: ["DuckAIChatCore", "DuckAIChatProviders", "DuckAIEvals"], swiftSettings: v5)
    ]
)
