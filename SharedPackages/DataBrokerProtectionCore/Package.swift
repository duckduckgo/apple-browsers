// swift-tools-version: 5.7
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
    name: "DataBrokerProtectionCore",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "DataBrokerProtectionCore",
            targets: ["DataBrokerProtectionCore"]),
        .library(name: "DataBrokerProtectionCoreTestsUtils", targets: ["DataBrokerProtectionCoreTestsUtils"]),
    ],
    dependencies: [
        .package(path: "../BrowserServicesKit"),
    ],
    targets: [
        .target(
            name: "DataBrokerProtectionCore",
            dependencies: [
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit"),
                .product(name: "Configuration", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
            ],
            resources: [.copy("Resources")],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "DataBrokerProtectionCoreTestsUtils",
            dependencies: [
                "DataBrokerProtectionCore",
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "PixelKit", package: "BrowserServicesKit"),
                .product(name: "Configuration", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "DataBrokerProtectionCoreTests",
            dependencies: [
                "DataBrokerProtectionCore",
                "DataBrokerProtectionCoreTestsUtils",
                "BrowserServicesKit",
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit"),
                .product(name: "SubscriptionTestingUtilities", package: "BrowserServicesKit"),
            ],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
