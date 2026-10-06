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
            name: "PreviewSnapshots",
            targets: ["PreviewSnapshots"]
        ),
        .library(
            name: "SnapshotTestingSupport",
            targets: ["SnapshotTestingSupport"]
        ),
    ],
    dependencies: [
        // Keep the reporting graph consistent across Xcode 26 and 27.
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.7.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.11.0"),
    ],
    targets: [
        .target(name: "PreviewSnapshots"),
        .target(
            name: "SnapshotTestingSupport",
            dependencies: [
                "PreviewSnapshots",
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
        .testTarget(
            name: "SnapshotTestingSupportTests",
            dependencies: [
                "SnapshotTestingSupport",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
