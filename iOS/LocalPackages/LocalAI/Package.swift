// swift-tools-version: 6.0
// PoC only (never merged): on-device answers for contextual-sheet actions.

import PackageDescription

let package = Package(
    name: "LocalAI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalAI", targets: ["LocalAI"]),
        .library(name: "LocalAIMLX", targets: ["LocalAIMLX"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "LocalAI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "LocalAIMLX",
            dependencies: [
                "LocalAI",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LocalAITests",
            dependencies: ["LocalAI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
