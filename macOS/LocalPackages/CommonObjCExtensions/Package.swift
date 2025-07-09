// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Package.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
    name: "CommonObjCExtensions",
    platforms: [
        .macOS("11.4")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(name: "BWIntegration", targets: ["BWIntegration"]),
        .library(name: "CommonObjCExtensions", targets: ["CommonObjCExtensions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/OpenSSL-XCFramework", exact: "3.3.2000")
    ],
    targets: [
        .target(
            name: "BWIntegration",
            dependencies: [
                .product(name: "OpenSSL", package: "OpenSSL-XCFramework")
            ],
            sources: [
                "BWEncryption.m",
                "BWEncryptionOutput.m",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "CommonObjCExtensions",
            dependencies: [],
            sources: [
                "NSException+Catch.m",
                "NSObject+performSelector.m",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        )
    ]
)
