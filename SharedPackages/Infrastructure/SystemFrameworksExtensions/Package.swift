// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.
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
    name: "SystemFrameworksExtensions",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "FoundationExtensions",
            targets: ["FoundationExtensions"]
        ),
        .library(
            name: "CombineExtensions",
            targets: ["CombineExtensions"]
        ),
        .library(
            name: "UIKitExtensions",
            targets: ["UIKitExtensionsProxy"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "3.0.0"),
    ],
    targets: [
        // MARK: - Shared Targets
        .target(
            name: "FoundationExtensions",
            dependencies: [
                .product(name: "Punycode", package: "PunycodeSwift"),
            ],
            exclude: ["README.md"]
        ),
        .target(
            name: "CombineExtensions"
        ),

        // MARK: - Platform Specific Targets
        .target(
            name: "UIKitExtensions"
        ),
        .target(
            name: "UIKitExtensionsProxy",
            dependencies: [
                .target(
                  name: "UIKitExtensions",
                  condition: .when(platforms: [.iOS])
                )
            ]
        ),

        // MARK: - Test Targets
        .testTarget(
            name: "FoundationExtensionsTests",
            dependencies: ["FoundationExtensions"]
        ),
    ]
)
