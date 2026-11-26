// swift-tools-version: 5.10
//
//  Package.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import PackageDescription

let package = Package(
    name: "LlamaRuntime",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(name: "LlamaRuntime", targets: ["LlamaRuntime"]),
    ],
    dependencies: [
        .package(path: "../DDGError"),
    ],
    targets: [
        // llama.cpp's headers, from the same release as the framework `embed_llama_framework.sh`
        // copies into the app. Nothing links llama.cpp: `cllama_load` opens it at runtime.
        // Temporary, for the internal release and evals: the hand-copied headers and the runtime
        // loading will be refactored before an external release.
        .target(
            name: "CLlama",
            exclude: ["LICENSE", "THIRD-PARTY-NOTICES"]
        ),
        .target(
            name: "LlamaRuntime",
            dependencies: ["CLlama", "DDGError"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LlamaRuntimeTests",
            dependencies: ["LlamaRuntime"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
