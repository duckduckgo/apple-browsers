// swift-tools-version: 5.10
//  Package.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Foundation

// Set by the "Build and test" step in .github/workflows/ios_pr_checks.yml. Under CI the package builds
// in release configuration (SPM maps the CI configuration to .release), so `.when(configuration: .debug)` below
// doesn't fire and the DEBUG-only snapshot tests wouldn't compile. This forces DEBUG on for that CI build.
let forceDebugForSnapshots = ProcessInfo.processInfo.environment["SPM_FORCE_DEBUG_FOR_SNAPSHOTS"] == "1"

let package = Package(
    name: "SyncUI-iOS",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SyncUI-iOS",
            targets: ["SyncUI-iOS"])
    ],
    dependencies: [
        .package(path: "../DuckUI"),
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKitIcons"),
        .package(path: "../../../SharedPackages/Infrastructure/DesignResourcesKit"),
        .package(path: "../../../SharedPackages/Infrastructure/MetricBuilder"),
        .package(path: "../../../SharedPackages/UIComponents"),
        .package(path: "../../../SharedPackages/SnapshotTestingSupport"),
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", exact: "3.2.1"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", exact: "4.6.1"),
    ],
    targets: [
        .target(
            name: "SyncUI-iOS",
            dependencies: [
                .product(name: "DuckUI", package: "DuckUI"),
                "DesignResourcesKit",
                .product(name: "DesignResourcesKitIcons", package: "DesignResourcesKitIcons"),
                .product(name: "MetricBuilder", package: "MetricBuilder"),
                .product(name: "UIComponents", package: "UIComponents"),
                .product(name: "Lottie", package: "lottie-spm"),
                .product(name: "PreviewSnapshots", package: "SnapshotTestingSupport"),
            ],
            resources: [
                .process("Resources/SyncMedia.xcassets"),
                .copy("Resources/SyncScanQRCode.lottie"),
                .copy("Resources/SyncLock.lottie")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ] + (forceDebugForSnapshots ? [.define("DEBUG")] : [])
        ),
        .testTarget(
            name: "SyncUI-iOSTests",
            dependencies: [
                "SyncUI-iOS",
                .product(name: "SnapshotTestingSupport", package: "SnapshotTestingSupport"),
            ]
        )
    ]
)
