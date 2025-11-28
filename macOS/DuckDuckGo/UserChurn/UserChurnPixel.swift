//
//  UserChurnPixel.swift
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
import PixelKit

enum UserChurnPixel: PixelKitEvent {

    case unsetAsDefault(newDefaultBrowserBundleId: String?, atb: String?)

    var name: String {
        switch self {
        case .unsetAsDefault:
            return "m_mac_unset-as-default"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .unsetAsDefault(let newDefaultBrowserBundleId, let atb):
            var params = ["newDefault": Self.browserName(from: newDefaultBrowserBundleId)]
            if let atb {
                params["atb"] = atb
            }
            return params
        }
    }

    private static func browserName(from bundleId: String?) -> String {
        guard let bundleId = bundleId?.lowercased() else {
            return "Other"
        }

        if bundleId.contains("chrome") {
            return "Chrome"
        } else if bundleId == "com.apple.safari" {
            return "Safari"
        } else if bundleId.contains("firefox") {
            return "Firefox"
        } else if bundleId.contains("brave") {
            return "Brave"
        } else {
            return "Other"
        }
    }
}
