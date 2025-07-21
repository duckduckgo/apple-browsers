//
//  OnboardingPrivacyProPromotionHelper.swift
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

/// Protocol defining the interface for the Privacy Pro onboarding promotion helper.
///
/// Conforming types provide logic for determining when the Privacy Pro promotion should be shown during onboarding,
/// as well as utilities for experiment tracking and pixel firing related to the promotion.
protocol OnboardingPrivacyProPromotionHelping {
    
    /// Text to display on the promotion proceed button
    var proceedButtonText: String { get }

    /// Indicates whether the Privacy Pro promotion should be displayed to the user during onboarding.
    var shouldDisplay: Bool { get }

    /// Provides the URL components for redirecting as part of the onboarding promotion experiment.
    ///
    /// - Returns: URL components for the experiment, or `nil` if not applicable.
    func redirectURLComponents() -> URLComponents?

    /// Fires a pixel when the onboarding promotion is shown to the user.
    func fireImpressionPixel()

    /// Fires a pixel when the onboarding promotion is tapped by the user.
    func fireTapPixel()

    /// Fires a pixel when the onboarding promotion is dismissed by the user.
    func fireDismissPixel()
}

/// A helper struct that implements the OnboardingPrivacyProPromotionHelping protocol.
///
/// This struct provides the logic for determining when to show the Privacy Pro promotion during onboarding,
/// as well as handling experiment tracking and pixel firing.
struct OnboardingPrivacyProPromotionHelper: OnboardingPrivacyProPromotionHelping {

    /// Constants used by the helper.
    enum Constants {
        /// The origin parameter value for this privacy pro promotion funnel.
        static let origin = "funnel_onboarding_ios"
    }

    /// The feature flagging service used to determine if the promotion should be shown.
    private let featureFlagger: FeatureFlagger

    /// The subscription manager used to check if the user can purchase a subscription.
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge

    /// The pixel firing service used to track user interactions with the promotion.
    private let pixelFiring: PixelFiring.Type

    /// Initializes a new instance of the OnboardingPrivacyProPromotionHelper.
    ///
    /// - Parameters:
    ///   - featureFlagger: The feature flagging service. Defaults to the shared instance.
    ///   - subscriptionManager: The subscription manager. Defaults to the shared instance.
    ///   - pixelFiring: The pixel firing service. Defaults to Pixel.self.
    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger, subscriptionManager: any SubscriptionAuthV1toV2Bridge = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge, pixelFiring: PixelFiring.Type = Pixel.self) {
        self.featureFlagger = featureFlagger
        self.subscriptionManager = subscriptionManager
        self.pixelFiring = pixelFiring
    }
    
    /// Text to display on the promotion proceed button
    ///
    /// This property checks if the user is eligible for a free trial and returns a suitable string to match their free trial eligibility.
    var proceedButtonText: String {
        subscriptionManager.isUserEligibleForFreeTrial() ? UserText.SubscriptionPromotionOnboarding.Buttons.tryItForFree : UserText.SubscriptionPromotionOnboarding.Buttons.learnMore
    }

    /// Indicates whether the Privacy Pro promotion should be displayed to the user during onboarding.
    ///
    /// This property checks if the feature flag is enabled and if the user can purchase a subscription.
    var shouldDisplay: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.privacyProOnboardingPromotion, allowOverride: true) && subscriptionManager.canPurchase
    }

    /// Provides the URL components for redirecting as part of the onboarding promotion experiment.
    ///
    /// - Returns: URL components for the experiment, or `nil` if not applicable.
    func redirectURLComponents() -> URLComponents? {
        SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.onboarding.rawValue)
    }

    /// Fires a pixel when the onboarding promotion is shown to the user.
    func fireImpressionPixel() {
        pixelFiring.fire(.privacyProOnboardingPromotionImpression, withAdditionalParameters: [:])
    }

    /// Fires a pixel when the onboarding promotion is tapped by the user.
    func fireTapPixel() {
        pixelFiring.fire(.privacyProOnboardingPromotionTap, withAdditionalParameters: [:])
    }

    /// Fires a pixel when the onboarding promotion is dismissed by the user.
    func fireDismissPixel() {
        pixelFiring.fire(.privacyProOnboardingPromotionDismiss, withAdditionalParameters: [:])
    }
}
