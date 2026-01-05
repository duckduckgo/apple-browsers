// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Package.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
    name: "TestUtilities",
    platforms: [
        .macOS("11.4")
    ],
    products: [
        .library(name: "NoARCObjCTestUtilities", targets: ["NoARCObjCTestUtilities"]),
        .library(name: "SharedTestUtilities", targets: ["SharedTestUtilities"]),
        .library(name: "SharedSandboxTestUtilities", targets: ["SharedSandboxTestUtilities"]),
    ],
    dependencies: [
        .package(path: "../Utilities"),
        .package(path: "../AppKitExtensions"),
        .package(path: "../../../SharedPackages/BrowserServicesKit"),
        .package(path: "../CommonObjCExtensions"),
    ],
    targets: [
        .target(
            name: "NoARCObjCTestUtilities",
            dependencies: [],
            sources: [
                "NSObject+AutoreleaseTracking.m",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .unsafeFlags(["-fno-objc-arc"], .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "SharedTestUtilities",
            dependencies: [
                .product(name: "AppKitExtensions", package: "AppKitExtensions"),
                .product(name: "CommonObjCExtensions", package: "CommonObjCExtensions"),
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "Navigation", package: "BrowserServicesKit"),
                .product(name: "Suggestions", package: "BrowserServicesKit"),
                .product(name: "SharedObjCTestsUtils", package: "BrowserServicesKit"),
                .product(name: "Utilities", package: "Utilities"),
            ]
        ),
        .target(
            name: "SharedSandboxTestUtilities",
            dependencies: [
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
