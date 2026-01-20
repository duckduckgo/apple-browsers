//
//  PreferencesPurchaseSubscriptionModel.swift
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

import AppKit
import Subscription
import struct Combine.AnyPublisher
import enum Combine.Publishers
import FeatureFlags
import PrivacyConfig
import os.log

public final class PreferencesPurchaseSubscriptionModel: ObservableObject {

    @Published var subscriptionStorefrontRegion: SubscriptionRegion = .usa
    @Published var isUserEligibleForFreeTrial: Bool = false

    var currentPurchasePlatform: SubscriptionEnvironment.PurchasePlatform { subscriptionManager.currentEnvironment.purchasePlatform }

    lazy var sheetModel = SubscriptionAccessViewModel(actionHandlers: sheetActionHandler,
                                                      purchasePlatform: subscriptionManager.currentEnvironment.purchasePlatform)

    var shouldDirectlyLaunchActivationFlow: Bool {
        subscriptionManager.currentEnvironment.purchasePlatform == .stripe
    }

    var shouldDisplayWinBackOffer: Bool {
        winBackOfferVisibilityManager.isOfferAvailable
    }

    var shouldDisplayBlackFridayCampaign: Bool {
        blackFridayCampaignProvider.isCampaignEnabled
    }

    var blackFridayDiscountPercent: Int {
        blackFridayCampaignProvider.discountPercent
    }

    // MARK: - Purchase Section UI Properties

    var purchaseSectionHeader: String {
        if shouldDisplayWinBackOffer {
            return UserText.winBackCampaignLoggedOutPreferencesTitle
        } else {
            return UserText.preferencesSubscriptionInactiveHeader(isPaidAIChatEnabled: isPaidAIChatEnabled)
        }
    }

    var purchaseSectionCaption: String {
        if shouldDisplayWinBackOffer {
            return UserText.winBackCampaignLoggedInPreferencesMessage
        } else {
            return UserText.preferencesSubscriptionInactiveCaption(region: subscriptionStorefrontRegion, isPaidAIChatEnabled: isPaidAIChatEnabled)
        }
    }

    var purchaseButtonTitle: String {
        if shouldDisplayWinBackOffer {
            return UserText.winBackCampaignLoggedOutPreferencesCTA
        } else if shouldDisplayBlackFridayCampaign {
            return UserText.blackFridayCampaignPreferencesCTA(discountPercent: blackFridayDiscountPercent)
        } else if isUserEligibleForFreeTrial {
            return UserText.purchaseFreeTrialButton
        } else {
            return UserText.purchaseButton
        }
    }

    private let subscriptionManager: SubscriptionManager
    private let userEventHandler: (PreferencesPurchaseSubscriptionModel.UserEvent) -> Void
    private let sheetActionHandler: SubscriptionAccessActionHandlers
    private let featureFlagger: FeatureFlagger
    private let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging
    private let blackFridayCampaignProvider: BlackFridayCampaignProviding

    public enum UserEvent {
        case didClickIHaveASubscription,
             openURL(SubscriptionURL),
             openWinBackOfferLandingPage
    }

    public init(subscriptionManager: SubscriptionManager,
                featureFlagger: FeatureFlagger,
                winBackOfferVisibilityManager: WinBackOfferVisibilityManaging,
                userEventHandler: @escaping (PreferencesPurchaseSubscriptionModel.UserEvent) -> Void,
                sheetActionHandler: SubscriptionAccessActionHandlers,
                blackFridayCampaignProvider: BlackFridayCampaignProviding) {
        self.subscriptionManager = subscriptionManager
        self.userEventHandler = userEventHandler
        self.sheetActionHandler = sheetActionHandler
        self.featureFlagger = featureFlagger
        self.winBackOfferVisibilityManager = winBackOfferVisibilityManager
        self.blackFridayCampaignProvider = blackFridayCampaignProvider
        self.subscriptionStorefrontRegion = currentStorefrontRegion()

        updateFreeTrialEligibility()
    }

    @MainActor
    func didAppear() {
        self.subscriptionStorefrontRegion = currentStorefrontRegion()
        updateFreeTrialEligibility()
    }

    @MainActor
    func purchaseAction() {
        if winBackOfferVisibilityManager.isOfferAvailable {
            userEventHandler(.openWinBackOfferLandingPage)
        } else {
            userEventHandler(.openURL(.purchase))
        }
    }

    @MainActor
    func didClickIHaveASubscription() {
        userEventHandler(.didClickIHaveASubscription)
    }

    @MainActor
    func openFAQ() {
        userEventHandler(.openURL(.faq))
    }

    @MainActor
    func openPrivacyPolicy() {
        userEventHandler(.openURL(.privacyPolicy))
    }

    var isPaidAIChatEnabled: Bool {
        featureFlagger.isFeatureOn(.paidAIChat) && subscriptionManager is DefaultSubscriptionManager
    }

    /// Updates the user's eligibility for a free trial based on subscription manager checks.
    ///
    /// This method queries the subscription manager to determine if the user is eligible for a free trial.
    ///
    /// - Note: This method updates the `isUserEligibleForFreeTrial` published property, which will
    ///         trigger UI updates for any observers.
    private func updateFreeTrialEligibility() {
        self.isUserEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
    }

    private func currentStorefrontRegion() -> SubscriptionRegion {
        return subscriptionManager.currentStorefrontRegion
    }
}
