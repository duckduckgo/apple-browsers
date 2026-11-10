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

// Set by the "Build and test" step in .github/workflows/ios_pr_checks.yml. Under CI the package builds
// in release configuration (SPM maps the CI configuration to .release), so `.when(configuration: .debug)` below
// doesn't fire and the DEBUG-only debug menu code wouldn't compile. This forces DEBUG on for that CI build.
let forceDebug = ProcessInfo.processInfo.environment["SPM_FORCE_DEBUG"] == "1"

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
        .package(path: "../../../SharedPackages/WideEvent"),
        .package(path: "../../../SharedPackages/Common"),
        .package(path: "../../../SharedPackages/Persistence"),
        .package(path: "../../../SharedPackages/PixelKit"),
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../../../SharedPackages/Infrastructure/SystemFrameworksExtensions"),
        .package(path: "../../../SharedPackages/DataBrokerProtectionCore"),
    ],
    targets: [
        .target(
            name: "DataBrokerProtection-iOS",
            dependencies: [
                .product(name: "WideEvent", package: "WideEvent"),
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "Common", package: "Common"),
                .product(name: "FoundationExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "CombineExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "ConcurrencyExtensions", package: "SystemFrameworksExtensions"),
                .product(name: "DataBrokerProtectionCore", package: "DataBrokerProtectionCore"),
                .product(name: "DataBrokerProtectionDebugServer", package: "DataBrokerProtectionCore"),
                .product(name: "PixelKit", package: "PixelKit"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "PrivacyConfig", package: "BrowserServicesKit"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ] + (forceDebug ? [.define("DEBUG")] : [])
        ),
        .testTarget(
            name: "DataBrokerProtection-iOSTests",
            dependencies: [
                "DataBrokerProtection-iOS",
                "DataBrokerProtectionCore",
                "BrowserServicesKit",
                .product(name: "Subscription", package: "BrowserServicesKit"),
                .product(name: "DataBrokerProtectionCoreTestsUtils", package: "DataBrokerProtectionCore"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "SubscriptionTestingUtilities", package: "BrowserServicesKit"),
            ]
        )
    ]
)
