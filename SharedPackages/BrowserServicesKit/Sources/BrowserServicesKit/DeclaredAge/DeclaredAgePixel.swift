//
//  DeclaredAgePixel.swift
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
import PixelKit

enum DeclaredAgePixel: PixelKit.Event {

    case checkNotRequired(isReinstall: Bool)
    case requestShown(isReinstall: Bool)
    case requestCompleted(isReinstall: Bool)
    case requestFailed(isReinstall: Bool)

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .checkNotRequired:
            return "declared-age_check_not-required" + platformSuffix
        case .requestShown:
            return "declared-age_request_shown" + platformSuffix
        case .requestCompleted:
            return "declared-age_request_completed" + platformSuffix
        case .requestFailed:
            return "declared-age_request_failed" + platformSuffix
        }
    }

    var parameters: [String: String]? {
#if os(macOS)
        // iOS can't detect a reinstall, so the parameter is macOS only.
        switch self {
        case .checkNotRequired(let isReinstall),
             .requestShown(let isReinstall),
             .requestCompleted(let isReinstall),
             .requestFailed(let isReinstall):
            return ["isReinstall": String(isReinstall)]
        }
#else
        return nil
#endif
    }

    var standardParameters: [PixelKitStandardParameter]? {
        nil
    }

    var error: NSError? {
        nil
    }

    private var platformSuffix: String {
#if os(macOS)
        "_macos"
#else
        ""
#endif
    }
}
