//
//  WebExtensionIdentifier.swift
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

import Foundation

@available(macOS 15.4, *)
enum WebExtensionIdentifier: String {
    case bitwarden

    static func identify(bundle: Bundle) -> WebExtensionIdentifier? {
        guard let bundleId = bundle.bundleIdentifier else {
            return nil
        }

        switch bundleId {
        case "com.bitwarden.desktop.safari":
            // Could add additional validation here (entitlements, version, etc.)
            return .bitwarden
        default:
            return nil
        }
    }

    var defaultPath: String {
        switch self {
        case .bitwarden:
            "file:///Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        }
    }
}
