//
//  AppRatingPromptPixel.swift
//  DuckDuckGo
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

/// Counts how often the app asks iOS for the App Store rating dialog. There are two requests per
/// install, so each of these fires at most once.
///
/// iOS decides whether it actually draws the dialog, using a yearly quota and the user's
/// Settings > App Store > In-App Ratings & Reviews toggle, and tells us nothing either way. These
/// therefore count requests, not impressions.
enum AppRatingPromptPixel: PixelKit.Event, Equatable {
    /// The first of the two per-install requests, due after 3 unique usage days.
    case firstRequest
    /// The second and final per-install request, due 4 unique usage days after the first.
    case secondRequest

    private enum Parameter {
        static let request = "request"
    }

    var name: String { "app-rating-prompt_requested" }

    var parameters: [String: String]? {
        switch self {
        case .firstRequest: return [Parameter.request: "first"]
        case .secondRequest: return [Parameter.request: "second"]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
