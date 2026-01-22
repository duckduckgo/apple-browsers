// swift-tools-version: 5.9
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
    name: "AIChat",
    defaultLocalization: "en",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "AIChat",
            targets: ["AIChat"]
        ),
        .library(
            name: "AIChatTestingUtilities",
            targets: ["AIChatTestingUtilities"]
        ),
    ],
    dependencies: [
        .package(path: "../Infrastructure/DesignResourcesKit"),
        .package(path: "../Infrastructure/DesignResourcesKitIcons"),
        .package(path: "../BrowserServicesKit"),
        .package(url: "https://github.com/duckduckgo/sync_crypto", exact: "0.7.0")
    ],
    targets: [
        .target(
            name: "AIChat",
            dependencies: [
                "DesignResourcesKit",
                "DesignResourcesKitIcons",
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "DDGSync", package: "BrowserServicesKit"),
                .product(name: "PrivacyConfig", package: "BrowserServicesKit"),
                .product(name: "UserScript", package: "BrowserServicesKit"),
                .product(name: "DDGSyncCrypto", package: "sync_crypto")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "AIChatTestingUtilities",
            dependencies: [
                "AIChat"
            ]
        ),
        .testTarget(
            name: "AIChatTests",
            dependencies: [
                "AIChat",
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit")
            ]
        )
    ]
)
