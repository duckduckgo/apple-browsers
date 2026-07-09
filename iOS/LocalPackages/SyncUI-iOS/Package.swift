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
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", exact: "3.2.1"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", exact: "4.5.2"),
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
                .product(name: "Lottie", package: "lottie-spm")
            ],
            resources: [
                .process("Resources/SyncMedia.xcassets"),
                .copy("Resources/SyncScanQRCode.lottie")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "SyncUI-iOSTests",
            dependencies: [
                "SyncUI-iOS"
            ]
        )
    ]
)
