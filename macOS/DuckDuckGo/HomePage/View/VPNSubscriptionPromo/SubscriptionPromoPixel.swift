//
//  SubscriptionPromoPixel.swift
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

enum SubscriptionPromoPixel: PixelKitEvent {
    case promoDisplayed(isEligibleForFreeTrial: Bool)
    case promoViewed(isEligibleForFreeTrial: Bool)
    case promoCtaActioned(isEligibleForFreeTrial: Bool)
    case promoDismissed(isEligibleForFreeTrial: Bool)

    var name: String {
        switch self {
        case .promoDisplayed: return "m_mac_fire_window_subscription_promo_displayed"
        case .promoViewed: return "m_mac_fire_window_subscription_promo_viewed"
        case .promoCtaActioned: return "m_mac_fire_window_subscription_promo_cta_actioned"
        case .promoDismissed: return "m_mac_fire_window_subscription_promo_dismissed"
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }

    var parameters: [String: String]? {
        switch self {
        case .promoDisplayed(let isEligibleForFreeTrial),
             .promoViewed(let isEligibleForFreeTrial),
             .promoCtaActioned(let isEligibleForFreeTrial),
             .promoDismissed(let isEligibleForFreeTrial):
            return ["free_trial": isEligibleForFreeTrial ? "true" : "false"]
        }
    }
}
