//
//  VPNSubscriptionPromotionHelper.swift
//  DuckDuckGo
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

import BrowserServicesKit
import Core
import Foundation
import Subscription

/// Protocol defining the interface for the VPN Subscription promotion helper.
///
/// Conforming types provide logic for determining how the Subscription should be promoted on the VPN menu item,
/// as well as utilities for persistence and pixel firing related to the promotion.
protocol VPNSubscriptionPromotionHelping {

    /// Status of the subscription promotion.
    var subscriptionPromoStatus: VPNSubscriptionPromotionStatus { get }

    /// Provides the URL components for subscribing as part of the promotion.
    func subscriptionURLComponents() -> URLComponents?

    /// Records when the promo has been shown to the user.
    func subscriptionPromoWasShown()

    /// Fires a pixel when the network protection promotion is tapped by the user.
    func fireTapPixel()
}

enum VPNSubscriptionPromotionStatus {
    case promo
    case noPromo
    case subscribed

    var pixelParameter: String {
        switch self {
        case .promo:
            return "pill"
        case .noPromo:
            return "no_pill"
        case .subscribed:
            return "subscribed"
        }
    }
}

/// A helper struct that implements the VPNSubscriptionPromotionHelping protocol.
///
/// This struct provides the logic for determining how the Subscription should be promoted on the VPN menu item,
/// as well as handling persistence and pixel firing.
struct VPNSubscriptionPromotionHelper: VPNSubscriptionPromotionHelping {

    /// The feature flagging service used to determine if the promotion should be shown.
    private let featureFlagger: FeatureFlagger

    /// The subscription manager used to check if the user has a subscription.
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge

    /// The persistor used to track and check how many times the promotion has been shown.
    private let freeTrialBadgePersistor: FreeTrialBadgePersisting

    /// The pixel firing service used to track user interactions with the promotion.
    private let pixelFiring: PixelFiring.Type

    /// Initializes a new instance of the VPNSubscriptionPromotionHelper.
    ///
    /// - Parameters:
    ///   - featureFlagger: The feature flagging service. Defaults to the shared instance.
    ///   - subscriptionManager: The subscription manager. Defaults to the shared instance.
    ///   - freeTrialBadgePersistor: The persistor for tracking promotion views. Defaults to an instance using UserDefaults and a custom key prefix.
    ///   - pixelFiring: The pixel firing service. Defaults to Pixel.self.
    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
         freeTrialBadgePersistor: FreeTrialBadgePersisting = FreeTrialBadgePersistor(keyValueStore: UserDefaults.standard, keyPrefix: "vpn-menu-item"),
         pixelFiring: PixelFiring.Type = Pixel.self) {
        self.featureFlagger = featureFlagger
        self.subscriptionManager = subscriptionManager
        self.freeTrialBadgePersistor = freeTrialBadgePersistor
        self.pixelFiring = pixelFiring
    }

    /// Status of the subscription promotion
    ///
    /// This property checks the subscription status and if the user should see the promotion and returns the status.
    var subscriptionPromoStatus: VPNSubscriptionPromotionStatus {
        if subscriptionManager.isSubscriptionPresent() {
            return .subscribed
        } else if shouldDisplayPromo {
            return .promo
        } else {
            return .noPromo
        }
    }

    /// Indicates whether the subscription promotion should be displayed to the user.
    ///
    /// This property checks:
    /// - If the feature flag is enabled
    /// - Whether the user has reached their limit for the promotion
    private var shouldDisplayPromo: Bool {
        featureFlagger.isFeatureOn(.vpnMenuItem) && !freeTrialBadgePersistor.hasReachedViewLimit
    }

    /// Provides the URL components for subscribing as part of the promotion.
    ///
    /// - Returns: URL components for the experiment, or `nil` if not applicable.
    func subscriptionURLComponents() -> URLComponents? {
        SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.newTabMenu.rawValue)
    }

    /// Records when the promotion has been shown to the user.
    func subscriptionPromoWasShown() {
        guard featureFlagger.isFeatureOn(.vpnMenuItem) else { return }
        freeTrialBadgePersistor.incrementViewCount()
    }

    /// Fires a pixel when the promotion is tapped by the user.
    func fireTapPixel() {
        pixelFiring.fire(.browsingMenuVPN, withAdditionalParameters: ["status": subscriptionPromoStatus.pixelParameter])
    }
}
