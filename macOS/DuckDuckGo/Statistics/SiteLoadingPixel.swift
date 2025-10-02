//
//  SiteLoadingPixel.swift
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

/// Tracks user navigation journey outcomes to measure site loading success rates.
/// Complements GeneralPixel.navigation (attempt tracking) with outcome-specific data.
enum SiteLoadingPixel: PixelKitEvent {

    /// Navigation completed successfully from user perspective
    case siteLoadingSuccess(duration: TimeInterval, navigationType: String)
    /// Navigation failed due to network/server/content issues
    case siteLoadingFailure(duration: TimeInterval, error: Error, navigationType: String)

    var name: String {
        switch self {
        case .siteLoadingSuccess:
            return "m_mac_site_loading_success"
        case .siteLoadingFailure:
            return "m_mac_site_loading_failure"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .siteLoadingSuccess(let duration, let navigationType):
            return [
                PixelKit.Parameters.duration: String(Int(duration * 1000)), // Milliseconds for precision
                "navigation_type": navigationType
            ]
        case .siteLoadingFailure(let duration, _, let navigationType):
            return [
                PixelKit.Parameters.duration: String(Int(duration * 1000)),
                "navigation_type": navigationType
            ]
        }
    }

    var error: NSError? {
        switch self {
        case .siteLoadingSuccess:
            return nil
        case .siteLoadingFailure(_, let error, _):
            return error as NSError
        }
    }
}
