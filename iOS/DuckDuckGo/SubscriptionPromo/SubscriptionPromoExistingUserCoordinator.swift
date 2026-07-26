//
//  SubscriptionPromoExistingUserCoordinator.swift
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

/// Coordinates the subscription promotion launch sheet for existing users who completed onboarding
/// normally (i.e. did not skip it) and have never seen a subscription offer.
///
/// Complements `SubscriptionPromoCoordinator`, which targets returning users who skipped onboarding.
/// Together, both coordinators ensure every install eventually sees a subscription offer, either
/// during onboarding or via one of these two launch prompts.
///
/// Self-contained: owns eligibility, pixel firing, and CTA navigation.
final class SubscriptionPromoExistingUserCoordinator: SubscriptionPromoCoordinating {

    static let cooldownDays = 7

    private var daxDialogs: any ContextualDaxDialogStatusProvider & SubscriptionPromotionCoordinating
    private let daxDialogsSettings: DaxDialogsSettings
    private let featureFlagger: FeatureFlagger
    private let tutorialSettings: TutorialSettings
    private let statisticsStore: StatisticsStore
    private let subscriptionManager: any SubscriptionManager
    private let pixelFiring: PixelFiring.Type

    init(
        daxDialogs: any ContextualDaxDialogStatusProvider & SubscriptionPromotionCoordinating,
        daxDialogsSettings: DaxDialogsSettings = DefaultDaxDialogsSettings(),
        featureFlagger: FeatureFlagger,
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        subscriptionManager: any SubscriptionManager,
        pixelFiring: PixelFiring.Type = Pixel.self
    ) {
        self.daxDialogs = daxDialogs
        self.daxDialogsSettings = daxDialogsSettings
        self.featureFlagger = featureFlagger
        self.tutorialSettings = tutorialSettings
        self.statisticsStore = statisticsStore
        self.subscriptionManager = subscriptionManager
        self.pixelFiring = pixelFiring
    }

    // MARK: - Eligibility

    /// Softer onboarding gate: eligible when onboarding is fully complete, or when no contextual
    /// onboarding dialog is currently visible on screen (`isShowingContextualOnboardingDialog`) —
    /// preventing the promo from appearing on top of an active "Try a Search",
    /// "Try Visiting a Site", or fire tutorial dialog on cold launch.
    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool {
        isOnboardingComplete || !daxDialogs.isShowingContextualOnboardingDialog
    }

    func shouldPresentLaunchPrompt() -> Bool {
        guard !daxDialogs.subscriptionPromotionDialogSeen else {
            Logger.subscription.debug("[Subscription Promo - Existing User] Promo already shown, skipping.")
            return false
        }
        let shouldShow = featureFlagger.isFeatureOn(for: FeatureFlag.subscriptionPromoForExistingUsers, allowOverride: true)
            && featureFlagger.isFeatureOn(for: FeatureFlag.privacyProOnboardingPromotion, allowOverride: true)
            && hasCooldownPassed()
            // Don't show for users who skipped onboarding: handled by SubscriptionPromoCoordinator
            && !(daxDialogsSettings.isDismissed && isReturningUser && tutorialSettings.hasSkippedOnboarding)

        Logger.subscription.debug("[Subscription Promo - Existing User] shouldPresentLaunchPrompt: \(shouldShow)")
        return shouldShow
    }

    func markLaunchPromptPresented() {
        daxDialogs.subscriptionPromotionDialogSeen = true
        Logger.subscription.debug("[Subscription Promo - Existing User] Launch prompt marked as presented.")
        firePixel(.subscriptionExistingUserPromotionImpression)
    }

    // MARK: - Content

    func promoTitle() -> String {
        UserText.SubscriptionPromotionOnboarding.Promo.delayedTitle
    }

    func proceedButtonText() -> String {
        subscriptionManager.isUserEligibleForFreeTrial()
        ? UserText.SubscriptionPromotionOnboarding.Buttons.Rebranding.tryItFree
            : UserText.SubscriptionPromotionOnboarding.Buttons.learnMore
    }

    func promoMessage() -> AttributedString {
        let markdown = UserText.SubscriptionPromotionOnboarding.Promo.reinstallerMessage
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    // MARK: - Actions

    func handleCTAAction() {
        Logger.subscription.debug("[Subscription Promo - Existing User] CTA action triggered.")
        firePixel(.subscriptionExistingUserPromotionTap)

        let origin = redirectOrigin()
        let comps = SubscriptionURL.purchaseURLComponentsWithOrigin(origin.rawValue)
        let deepLink = SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: comps)
        NotificationCenter.default.post(name: .settingsDeepLinkNotification, object: deepLink)
    }

    func handleDismissAction() {
        Logger.subscription.debug("[Subscription Promo - Existing User] Dismiss action triggered.")
        firePixel(.subscriptionExistingUserPromotionDismiss)
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
        .existingUserPromo
    }
}
