//
//  OnboardingSubscriptionPromotionHelper.swift
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
import PrivacyConfig
import Core
import Foundation
import Subscription

/// Protocol defining the interface for the Subscription onboarding promotion helper.
///
/// Conforming types provide logic for determining when the Subscription promotion should be shown during onboarding,
/// as well as utilities for experiment tracking and pixel firing related to the promotion.
protocol OnboardingSubscriptionPromotionHelping {

    /// Text to display on the promotion proceed button
    var proceedButtonText: String { get }

    /// Whether the feature flag is enabled and the user can purchase a subscription.
    /// Used as a base eligibility check before showing the promotion.
    var isFeatureEnabled: Bool { get }

    /// Whether the subscription promotion should be shown to a user who skipped onboarding.
    /// Requires base eligibility (`isFeatureEnabled`), the skip flag, and a 7-day cooldown since install.
    /// Returns `false` for users who completed onboarding normally — those go through the standard Dax dialog flow.
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

/// A helper struct that implements the OnboardingSubscriptionPromotionHelping protocol.
///
/// This struct provides the logic for determining when to show the Subscription promotion during onboarding,
/// as well as handling experiment tracking and pixel firing.
struct OnboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping {

    /// Whether the user is a returning user (reinstall) based on the `ru` variant in the statistics store.
    var isReturningUser: Bool {
        statisticsStore.variant == VariantIOS.returningUser.name
    }

    /// Whether the user is eligible for a free trial offer.
    var isFreeTrialEligible: Bool {
        subscriptionManager.isUserEligibleForFreeTrial()
    }

    /// The number of days after install before showing the promotion to users who skipped onboarding.
    static let skipOnboardingCooldownDays = 7

    /// The feature flagging service used to determine if the promotion should be shown.
    private let featureFlagger: FeatureFlagger

    /// The subscription manager used to check if the user can purchase a subscription.
    private let subscriptionManager: any SubscriptionManager

    /// The pixel firing service used to track user interactions with the promotion.
    private let pixelFiring: PixelFiring.Type

    /// The tutorial settings used to check if the user skipped onboarding.
    private let tutorialSettings: TutorialSettings

    /// The statistics store used to access the install date.
    private let statisticsStore: StatisticsStore

    /// A closure providing the current date, for testability.
    private let currentDateProvider: () -> Date

    /// Initializes a new instance of the OnboardingSubscriptionPromotionHelper.
    ///
    /// - Parameters:
    ///   - featureFlagger: The feature flagging service. Defaults to the shared instance.
    ///   - subscriptionManager: The subscription manager. Defaults to the shared instance.
    ///   - pixelFiring: The pixel firing service. Defaults to Pixel.self.
    ///   - tutorialSettings: The tutorial settings. Defaults to `DefaultTutorialSettings()`.
    ///   - statisticsStore: The statistics store. Defaults to `StatisticsUserDefaults()`.
    ///   - currentDateProvider: A closure providing the current date. Defaults to `Date.init`.
    init(
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
        subscriptionManager: any SubscriptionManager = AppDependencyProvider.shared.subscriptionManager,
        pixelFiring: PixelFiring.Type = Pixel.self,
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        currentDateProvider: @escaping () -> Date = { Date() }
    ) {
        self.featureFlagger = featureFlagger
        self.subscriptionManager = subscriptionManager
        self.pixelFiring = pixelFiring
        self.tutorialSettings = tutorialSettings
        self.statisticsStore = statisticsStore
        self.currentDateProvider = currentDateProvider
    }
    
    /// Text to display on the promotion proceed button
    ///
    /// This property checks if the user is eligible for a free trial and returns a suitable string to match their free trial eligibility.
    var proceedButtonText: String {
        subscriptionManager.isUserEligibleForFreeTrial() ? UserText.SubscriptionPromotionOnboarding.Buttons.tryItForFree : UserText.SubscriptionPromotionOnboarding.Buttons.learnMore
    }

    var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.privacyProOnboardingPromotion, allowOverride: true) && subscriptionManager.hasAppStoreProductsAvailable
    }

    var isReinstallerPromoEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.subscriptionPromoForReinstallers, allowOverride: true)
    }

    var shouldDisplay: Bool {
        guard isFeatureEnabled, isReinstallerPromoEnabled, tutorialSettings.hasSkippedOnboarding else { return false }
        guard let installDate = statisticsStore.installDate else { return false }
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: currentDateProvider()).day ?? 0
        return daysSinceInstall >= Self.skipOnboardingCooldownDays
    }

    /// Provides the URL components for redirecting as part of the onboarding promotion experiment.
    ///
    /// The origin encodes the user's returning/new status and free trial eligibility for attribution.
    ///
    /// - Returns: URL components for the experiment, or `nil` if not applicable.
    func redirectURLComponents() -> URLComponents? {
        let origin: SubscriptionFunnelOrigin = switch (isReturningUser, isFreeTrialEligible) {
        case (true, true): .onboardingReinstallFreeTrial
        case (true, false): .onboardingReinstallSubscribe
        case (false, true): .onboardingNewInstallFreeTrial
        case (false, false): .onboardingNewInstallSubscribe
        }
        return SubscriptionURL.purchaseURLComponentsWithOrigin(origin.rawValue)
    }

    /// Fires a pixel when the onboarding promotion is shown to the user.
    func fireImpressionPixel() {
        pixelFiring.fire(.subscriptionOnboardingPromotionImpression, withAdditionalParameters: promotionPixelParameters)
    }

    /// Fires a pixel when the onboarding promotion is tapped by the user.
    func fireTapPixel() {
        pixelFiring.fire(.subscriptionOnboardingPromotionTap, withAdditionalParameters: promotionPixelParameters)
    }

    /// Fires a pixel when the onboarding promotion is dismissed by the user.
    func fireDismissPixel() {
        pixelFiring.fire(.subscriptionOnboardingPromotionDismiss, withAdditionalParameters: promotionPixelParameters)
    }

    private var promotionPixelParameters: [String: String] {
        [
            PixelParameters.returningUser: isReturningUser ? "true" : "false",
            PixelParameters.freeTrial: isFreeTrialEligible ? "true" : "false"
        ]
    }
}
