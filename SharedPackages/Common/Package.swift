// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.
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
    name: "Common",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(name: "Common", targets: ["Common"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "3.0.0"),
        .package(path: "../URLPredictor"),
        .package(path: "../Infrastructure/SystemFrameworksExtensions"),
    ],
    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Punycode", package: "PunycodeSwift"),
                .product(name: "URLPredictor", package: "URLPredictor"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("_ORIGINAL_DATA_AS_STRING_ENABLED", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common",
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            swiftSettings: [
                .define("_ORIGINAL_DATA_AS_STRING_ENABLED", .when(platforms: [.macOS])),
            ]
        ),
    ]
)
