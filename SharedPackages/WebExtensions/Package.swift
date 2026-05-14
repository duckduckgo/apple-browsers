// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.
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
    name: "WebExtensions",
    platforms: [
        .iOS("15.0"),
        .macOS("11.4")
    ],
    products: [
        .library(
            name: "WebExtensions",
            targets: ["WebExtensions"]
        ),
    ],
    dependencies: [
        .package(path: "../BrowserServicesKit"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(
            name: "WebExtensions",
            dependencies: [
                .product(name: "Common", package: "BrowserServicesKit"),
                .product(name: "BrowserServicesKit", package: "BrowserServicesKit"),
                .product(name: "Persistence", package: "BrowserServicesKit"),
                "ZIPFoundation",
            ],
            resources: [
                .copy("BundledWebExtensions")
            ]
        ),
        .testTarget(
            name: "WebExtensionsTests",
            dependencies: [
                "WebExtensions",
                .product(name: "Persistence", package: "BrowserServicesKit"),
                .product(name: "PersistenceTestingUtils", package: "BrowserServicesKit"),
                .product(name: "PrivacyConfigTestsUtils", package: "BrowserServicesKit")
            ]
        ),
    ]
)
