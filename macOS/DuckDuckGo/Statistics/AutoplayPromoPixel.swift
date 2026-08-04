//
//  AutoplayPromoPixel.swift
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

import PixelKit

/// Pixels for the Autoplay Discoverability Promo, which auto-opens the Permission Center the first time a page displays the autoplay policy.
/// - Note: The promo runs at most once per install, so plain standard pixels are enough to bound their volume.
enum AutoplayPromoPixel: PixelKitEvent, Equatable {

    case shown
    case engaged
    case autoDismissed
    case settingsLinkClicked

    // MARK: - PixelKitEvent

    var name: String {
        switch self {
        case .shown:
            return "autoplay-promo_shown"
        case .engaged:
            return "autoplay-promo_engaged"
        case .autoDismissed:
            return "autoplay-promo_auto-dismissed"
        case .settingsLinkClicked:
            return "autoplay-promo_settings-click"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}
