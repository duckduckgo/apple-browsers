// swift-tools-version: 5.9
//
//  Package.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
    name: "LocalizationTool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "localization-tool", targets: ["LocalizationTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SmartlingAPIClient",
            dependencies: [],
            path: "Sources/SmartlingAPIClient"
        ),
        .executableTarget(
            name: "LocalizationTool",
            dependencies: [
                "SmartlingAPIClient",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/LocalizationTool"
        )
    ]
)
