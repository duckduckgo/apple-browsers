//
//  BundledDebugWebExtensions.swift
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

import Foundation

/// Test extensions bundled with the app, which the Debug menu installs on request.
public protocol BundledDebugWebExtensionsProtocol {
    /// An extension whose popup requests `nativeMessaging` at runtime, alone and with `tabs`.
    var nativeMessagingTestExtensionURL: URL? { get }
}

/// Finds the test extensions in the package's `BundledWebExtensions` folder.
/// Their sources are in `WebExtensionSources/`, each with a `build.sh` that regenerates the zip.
public struct BundledDebugWebExtensions: BundledDebugWebExtensionsProtocol {
    public init() {}

    public var nativeMessagingTestExtensionURL: URL? {
        Bundle.module.url(forResource: "native-messaging-test-extension", withExtension: "zip", subdirectory: "BundledWebExtensions")
    }
}
