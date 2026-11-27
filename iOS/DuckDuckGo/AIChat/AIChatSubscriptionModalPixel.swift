//
//  AIChatSubscriptionModalPixel.swift
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
import Subscription

/// Clicks on the subscribe and upgrade-to-Pro modals that Duck.ai's subscription entry points open.
/// The web frontend reports them over `reportMetric`; `origin` is the entry point that opened the modal.
enum AIChatSubscriptionModalPixel: PixelKit.Event {

    /// The subscribe CTA in the subscribe modal was tapped.
    case subscribeModalSubscribeClick(origin: SubscriptionFunnelOrigin)

    /// The upgrade CTA in the upgrade-to-Pro modal was tapped.
    case upgradeToProModalUpgradeClick(origin: SubscriptionFunnelOrigin)

    var name: String {
        switch self {
        case .subscribeModalSubscribeClick: return "aichat_subscription-funnel_subscribe-modal_subscribe_click"
        case .upgradeToProModalUpgradeClick: return "aichat_subscription-funnel_upgrade-to-pro-modal_upgrade_click"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .subscribeModalSubscribeClick(let origin),
                .upgradeToProModalUpgradeClick(let origin):
            return [AttributionParameter.origin: origin.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
