//
//  SubscriptionPromoCoordinator.swift
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

import BrowserServicesKit
import Core
import Foundation
import PrivacyConfig
import Subscription

/// Coordinates the subscription promotion launch sheet for users who skipped onboarding.
///
/// Self-contained: owns eligibility, pixel firing, and CTA navigation.
/// Uses only stable, synchronous signals — no dependency on async product availability.
protocol SubscriptionPromoCoordinating: AnyObject {
    func shouldPresentLaunchPrompt() -> Bool
    func markLaunchPromptPresented()
    func promoTitle() -> String
    func proceedButtonText() -> String
    func promoMessage() -> String
    func handleCTAAction()
    func handleDismissAction()
}

final class SubscriptionPromoCoordinator: SubscriptionPromoCoordinating {

    static let cooldownDays = 7

    private let daxDialogsSettings: DaxDialogsSettings
    private let featureFlagger: FeatureFlagger
    private let tutorialSettings: TutorialSettings
    private let statisticsStore: StatisticsStore
    private let subscriptionManager: any SubscriptionManager
    private let pixelFiring: PixelFiring.Type

    init(
        daxDialogsSettings: DaxDialogsSettings = DefaultDaxDialogsSettings(),
        featureFlagger: FeatureFlagger,
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        subscriptionManager: any SubscriptionManager,
        pixelFiring: PixelFiring.Type = Pixel.self
    ) {
        self.daxDialogsSettings = daxDialogsSettings
        self.featureFlagger = featureFlagger
        self.tutorialSettings = tutorialSettings
        self.statisticsStore = statisticsStore
        self.subscriptionManager = subscriptionManager
        self.pixelFiring = pixelFiring
    }

    // MARK: - Eligibility

    func shouldPresentLaunchPrompt() -> Bool {
        guard !daxDialogsSettings.subscriptionPromotionDialogShown else {
            Logger.subscription.debug("[Subscription Promo] Promo already shown, skipping.")
            return false
        }
        let shouldShow = featureFlagger.isFeatureOn(for: FeatureFlag.subscriptionPromoForReinstallers, allowOverride: true)
            && featureFlagger.isFeatureOn(for: FeatureFlag.privacyProOnboardingPromotion, allowOverride: true)
            && isReturningUser
            && tutorialSettings.hasSkippedOnboarding
            && hasCooldownPassed()
        Logger.subscription.debug("[Subscription Promo] shouldPresentLaunchPrompt: \(shouldShow)")
        return shouldShow
    }

    func markLaunchPromptPresented() {
        daxDialogsSettings.subscriptionPromotionDialogShown = true
        Logger.subscription.debug("[Subscription Promo] Launch prompt marked as presented.")
        firePixel(.subscriptionOnboardingPromotionImpression)
    }

    // MARK: - Content

    func promoTitle() -> String {
        UserText.SubscriptionPromotionOnboarding.Promo.delayedTitle
    }

    func proceedButtonText() -> String {
        subscriptionManager.isUserEligibleForFreeTrial()
            ? UserText.SubscriptionPromotionOnboarding.Buttons.tryItForFree
            : UserText.SubscriptionPromotionOnboarding.Buttons.learnMore
    }

    func promoMessage() -> String {
        let text = UserText.SubscriptionPromotionOnboarding.Promo.self
        return String(format: text.messageFormat, text.optionalSubscriptionBold, text.vpnBold, text.privateAIBold)
    }

    // MARK: - Actions

    func handleCTAAction() {
        Logger.subscription.debug("[Subscription Promo] CTA action triggered.")
        firePixel(.subscriptionOnboardingPromotionTap)

        let origin = redirectOrigin()
        let comps = SubscriptionURL.purchaseURLComponentsWithOrigin(origin.rawValue)
        let deepLink = SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: comps)
        NotificationCenter.default.post(name: .settingsDeepLinkNotification, object: deepLink)
    }

    func handleDismissAction() {
        Logger.subscription.debug("[Subscription Promo] Dismiss action triggered.")
        firePixel(.subscriptionOnboardingPromotionDismiss)
    }

    // MARK: - Private

    private func hasCooldownPassed() -> Bool {
        guard let installDate = statisticsStore.installDate else { return false }
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return daysSinceInstall >= Self.cooldownDays
    }

    private var isReturningUser: Bool {
        statisticsStore.variant == VariantIOS.returningUser.name
    }

    private var isFreeTrialEligible: Bool {
        subscriptionManager.isUserEligibleForFreeTrial()
    }

    private var pixelParameters: [String: String] {
        [
            PixelParameters.returningUser: isReturningUser ? "true" : "false",
            PixelParameters.freeTrial: isFreeTrialEligible ? "true" : "false"
        ]
    }

    private func firePixel(_ event: Pixel.Event) {
        pixelFiring.fire(event, withAdditionalParameters: pixelParameters)
    }

    private func redirectOrigin() -> SubscriptionFunnelOrigin {
        .skippedOnboarding
    }
}
