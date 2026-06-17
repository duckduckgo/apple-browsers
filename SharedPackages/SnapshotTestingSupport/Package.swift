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
    name: "SnapshotTestingSupport",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(
            name: "SnapshotTestingSupport",
            targets: ["SnapshotTestingSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.2"),
    ],
    targets: [
        .target(
            name: "SnapshotTestingSupport",
            dependencies: [
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
        .testTarget(
            name: "SnapshotTestingSupportTests",
            dependencies: ["SnapshotTestingSupport"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
