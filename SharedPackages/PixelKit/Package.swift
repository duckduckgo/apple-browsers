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
    name: "PixelKit",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(name: "PixelKit", targets: ["PixelKit"]),
        .library(name: "PixelKitTestingUtilities", targets: ["PixelKitTestingUtilities"]),
    ],
    dependencies: [
        .package(path: "../DDGError"),
        .package(path: "../Common"),
        .package(path: "../Persistence"),
        .package(path: "../Infrastructure/SystemFrameworksExtensions"),
    ],
    targets: [
        .target(
            name: "PixelKit",
            dependencies: [
                .product(name: "DDGError", package: "DDGError"),
                .product(name: "Common", package: "Common"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
            ],
            exclude: [
                "README.md",
                "RetryQueue/README.md"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PixelKitTestingUtilities",
            dependencies: [
                "PixelKit"
            ]
        ),
        .testTarget(
            name: "PixelKitTests",
            dependencies: [
                "PixelKit",
                "PixelKitTestingUtilities",
                .product(name: "PersistenceTestingUtils", package: "Persistence"),
            ]
        ),
    ]
)
