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
    name: "ReaderMode",
    platforms: [
        .macOS("12.3")
    ],
    products: [
        .library(
            name: "ReaderMode",
            targets: ["ReaderMode"]),
    ],
    targets: [
        .target(
            name: "ReaderMode",
            dependencies: ["Trafilatura"]
        ),
        // Upstream trafilatura-swift ships a static library, which clashes with the app's other Rust static library.
        // The fork builds a dynamic framework. The bindings must come from the same release as the binary.
        .binaryTarget(
            name: "TrafilaturaFFI",
            url: "https://github.com/ayoy/trafilatura-rs/releases/download/v0.5.0-ddg.1/TrafilaturaFFI.xcframework.zip",
            checksum: "5c7d747e8132229d09c7e447cfe42e756d4717e3408dd304706b745b59cef625"
        ),
        .target(
            name: "Trafilatura",
            dependencies: ["TrafilaturaFFI"],
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .testTarget(
            name: "ReaderModeTests",
            dependencies: ["ReaderMode"],
            resources: [.copy("Resources")]
        ),
    ]
)
