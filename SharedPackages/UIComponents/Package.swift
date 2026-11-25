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
import Foundation

// Set by the iOS "Build and test" CI step. Under CI, SPM builds packages in release configuration, so
// `.when(configuration: .debug)` below doesn't fire and the DEBUG-only previews and snapshot tests wouldn't
// compile. This forces DEBUG on for that build. Mirrors SyncUI-iOS/Package.swift.
let forceDebug = ProcessInfo.processInfo.environment["SPM_FORCE_DEBUG"] == "1"

let package = Package(
    name: "UIComponents",
    platforms: [
        .iOS("15.0"),
        .macOS("12.3")
    ],
    products: [
        .library(
            name: "UIComponents",
            targets: ["UIComponents"]),
    ],
    dependencies: [
        .package(path: "../Infrastructure/DesignResourcesKit"),
        .package(path: "../Infrastructure/DesignResourcesKitIcons"),
        .package(path: "../SnapshotTestingSupport"),
    ],
    targets: [
        .target(
            name: "UIComponents",
            dependencies: [
                "DesignResourcesKit",
                "DesignResourcesKitIcons",
                .product(name: "PreviewSnapshots", package: "SnapshotTestingSupport"),
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ] + (forceDebug ? [.define("DEBUG")] : [])
        ),
        .testTarget(
            name: "UIComponentsTests",
            dependencies: [
                "UIComponents",
                .product(name: "SnapshotTestingSupport", package: "SnapshotTestingSupport"),
            ]
        ),
    ]
)
