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
    name: "PIRDebugCLI",
    platforms: [
        .macOS("12.3")
    ],
    products: [
        .executable(name: "pir-debug", targets: ["pir-debug"]),
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../../../SharedPackages/DataBrokerProtectionCore"),
        .package(path: "../../../SharedPackages/DebugServer"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    ],
    targets: [
        .executableTarget(
            name: "pir-debug",
            dependencies: [
                .product(name: "PIRDebugKit", package: "DataBrokerProtectionCore"),
                .product(name: "Networking", package: "BrowserServicesKit"),
                .product(name: "DataBrokerProtectionCore", package: "DataBrokerProtectionCore"),
                .product(name: "DebugServer", package: "DebugServer"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
    ]
)
