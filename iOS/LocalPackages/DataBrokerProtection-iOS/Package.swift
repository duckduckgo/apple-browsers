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
    name: "DataBrokerProtection-iOS",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "DataBrokerProtection-iOS",
            targets: ["DataBrokerProtection-iOS"])
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../../../SharedPackages/DataBrokerProtectionCore"),
    ],
    targets: [
        .target(
            name: "DataBrokerProtection-iOS",
            dependencies: [
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "DataBrokerProtectionCore", package: "DataBrokerProtectionCore"),
                .product(name: "PixelKit", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "DataBrokerProtection-iOSTests",
            dependencies: [
                "DataBrokerProtection-iOS",
                "DataBrokerProtectionCore",
                "BrowserServicesKit",
                .product(name: "DataBrokerProtectionCoreTestsUtils", package: "DataBrokerProtectionCore"),
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit"),
                .product(name: "SubscriptionTestingUtilities", package: "BrowserServicesKit"),
            ]
        )
    ]
)
