// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Package.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
    name: "LetsMove",
    platforms: [
        .macOS("11.4")
    ],
    products: [
        // Header-only module that both App Store and DMG builds can import
        .library(name: "LetsMove", targets: ["LetsMove"]),
        // Real implementation for Sparkle/DMG builds
        .library(name: "LetsMoveImpl", targets: ["LetsMoveImpl"]),
        // Dummy/stub implementation for App Store builds
        .library(name: "LetsMoveDummy", targets: ["LetsMoveDummy"]),
    ],
    dependencies: [
    ],
    targets: [
        // Header-only target with just the interface
        .target(
            name: "LetsMove",
            publicHeadersPath: "include"
        ),
        // Real implementation target (for Sparkle/DMG builds)
        .target(
            name: "LetsMoveImpl",
            dependencies: ["LetsMove"],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fno-objc-arc"])
            ]
        ),
        // Dummy implementation target (for App Store builds)
        .target(
            name: "LetsMoveDummy",
            dependencies: ["LetsMove"],
            publicHeadersPath: "include"
        )
    ]
)
