//
//  WKWebExtensionContext+Extension.swift
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

import Foundation
import WebKit

/// Custom manifest key used to identify DuckDuckGo-specific extension types.
/// This key can be added to an extension's manifest.json to specify its type for handler registration.
private let duckDuckGoExtensionTypeManifestKey = "_duckduckgo_extension_type"

/// DuckDuckGo extension types.
@available(macOS 15.4, iOS 18.4, *)
public enum DuckDuckGoExtensionType: String {
    case ddgInternalExtension
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtensionContext {

    /// Returns the DuckDuckGo extension type from the manifest, if present.
    var duckDuckGoExtensionType: DuckDuckGoExtensionType? {
        guard let extensionTypeString = webExtension.manifest[duckDuckGoExtensionTypeManifestKey] as? String else {
            return nil
        }
        return DuckDuckGoExtensionType(rawValue: extensionTypeString)
    }
}
