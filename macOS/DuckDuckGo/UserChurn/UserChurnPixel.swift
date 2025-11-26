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

    case unsetAsDefault(newDefaultBrowserURL: URL?, atb: String?)

    var name: String {
        switch self {
        case .unsetAsDefault:
            return "m_mac_unset-as-default"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .unsetAsDefault(let newDefaultBrowserURL, let atb):
            var params = ["newDefault": Self.browserName(from: newDefaultBrowserURL)]
            if let atb {
                params["atb"] = atb
            }
            return params
        }
    }

    private static func browserName(from url: URL?) -> String {
        guard let url else {
            return "Other"
        }

        let path = url.path.lowercased()

        if path.contains("google chrome") {
            return "Chrome"
        } else if path.contains("safari") {
            return "Safari"
        } else if path.contains("firefox") {
            return "Firefox"
        } else if path.contains("brave") {
            return "Brave"
        } else {
            return "Other"
        }
    }
}
