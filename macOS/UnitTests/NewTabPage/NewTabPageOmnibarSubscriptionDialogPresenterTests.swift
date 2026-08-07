//
//  NewTabPageOmnibarSubscriptionDialogPresenterTests.swift
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

import Testing
import Foundation
import AIChat
import NewTabPage
@testable import DuckDuckGo_Privacy_Browser
import Subscription
import SubscriptionTestingUtilities

@MainActor
struct NewTabPageOmnibarSubscriptionDialogPresenterTests {

    // MARK: - Test Setup

    private func createPresenter(isEligibleForFreeTrial: Bool = false) -> (NewTabPageOmnibarSubscriptionDialogPresenter, MockSubscriptionTabsShowing, SubscriptionManagerMock) {
        let mockTabShower = MockSubscriptionTabsShowing()
        let mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionManager.resultURL = URL(string: "https://duckduckgo.com/pro")!
        mockSubscriptionManager.isEligibleForFreeTrialResult = isEligibleForFreeTrial
        let coordinator = SubscriptionNavigationCoordinator(
            tabShower: mockTabShower,
            subscriptionManager: mockSubscriptionManager
        )
        let presenter = NewTabPageOmnibarSubscriptionDialogPresenter(coordinator: coordinator, subscriptionManager: mockSubscriptionManager)
        return (presenter, mockTabShower, mockSubscriptionManager)
    }

    // MARK: - Upsell (subscribe) dialog

    @available(iOS 16, macOS 13, *)
    @Test("Upsell dialog offers a free trial when the user is free-tier and still eligible", .timeLimit(.minutes(1)))
    func upsellDialogOffersFreeTrialWhenEligible() async throws {
        let (presenter, _, _) = createPresenter(isEligibleForFreeTrial: true)
        let dialog = presenter.makeUpsellDialog(userTier: .free, source: .model)

        #expect(dialog.primaryButtonText == UserText.aiChatSubscriptionUpsellDialogTryForFreeButton)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Upsell dialog reads Upgrade once the user isn't free-trial eligible, and routes to the purchase flow", .timeLimit(.minutes(1)))
    func upsellDialogRoutesToPurchase() async throws {
        let (presenter, mockTabShower, _) = createPresenter(isEligibleForFreeTrial: false)
        let dialog = presenter.makeUpsellDialog(userTier: .free, source: .model)

        #expect(dialog.primaryButtonText == UserText.aiChatSubscriptionUpsellDialogUpgradeButton)

        dialog.onSubscribe?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url.absoluteString.contains("featurePage=duckai"))
        #expect(url.absoluteString.contains("origin=funnel_newtab_macos__modelpicker"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Upsell dialog reads Upgrade for a non-free tier even when StoreKit reports free-trial eligibility", .timeLimit(.minutes(1)))
    func upsellDialogIgnoresFreeTrialEligibilityForNonFreeTier() async throws {
        let (presenter, _, _) = createPresenter(isEligibleForFreeTrial: true)
        let dialog = presenter.makeUpsellDialog(userTier: .plus, source: .model)

        #expect(dialog.primaryButtonText == UserText.aiChatSubscriptionUpsellDialogUpgradeButton)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Upsell dialog's 'I Have a Subscription' button routes to activation", .timeLimit(.minutes(1)))
    func upsellDialogHaveSubscriptionRoutesToActivation() async throws {
        let (presenter, mockTabShower, _) = createPresenter()
        let dialog = presenter.makeUpsellDialog(userTier: .free, source: .model)

        dialog.onHaveSubscription?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        // Activation doesn't append featurePage/origin — only purchase/plans do.
        #expect(!url.absoluteString.contains("featurePage"))
    }

    // MARK: - Upgrade dialog

    @available(iOS 16, macOS 13, *)
    @Test("Upgrade dialog uses the Pro title/message, hides the Have-Subscription button, and routes to the plans flow", .timeLimit(.minutes(1)))
    func upgradeDialogRoutesToPlans() async throws {
        let (presenter, mockTabShower, _) = createPresenter()
        let dialog = presenter.makeUpgradeDialog(source: .model)

        #expect(dialog.title == UserText.aiChatSubscriptionUpsellDialogProTitle)
        #expect(dialog.message == UserText.aiChatSubscriptionUpsellDialogProMessage)
        #expect(dialog.primaryButtonText == UserText.aiChatSubscriptionUpsellDialogUpgradeButton)
        #expect(dialog.showsHaveSubscriptionButton == false)

        dialog.onSubscribe?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url.absoluteString.contains("featurePage=duckai"))
        #expect(url.absoluteString.contains("origin=funnel_newtab_macos__modelpicker"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("The gated picker decides the funnel origin", .timeLimit(.minutes(1)))
    func pickerDecidesOrigin() async throws {
        // Not parameterized: `OmnibarSubscriptionUpsellSource` isn't Sendable, so passing it as a
        // test argument warns today and fails under the Swift 6 language mode.
        for (source, expectedOrigin) in [(NewTabPageDataModel.OmnibarSubscriptionUpsellSource.model, "funnel_newtab_macos__modelpicker"),
                                         (.reasoning, "funnel_newtab_macos__reasoningdropdown")] {
            let (presenter, mockTabShower, _) = createPresenter()

            presenter.makeUpsellDialog(userTier: .free, source: source).onSubscribe?()

            guard case let .subscription(url) = mockTabShower.capturedContent else {
                Issue.record("Expected .subscription tab content for \(source)")
                return
            }
            #expect(url.absoluteString.contains("origin=\(expectedOrigin)"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Upgrade dialog's 'I Have a Subscription' button routes to activation", .timeLimit(.minutes(1)))
    func upgradeDialogHaveSubscriptionRoutesToActivation() async throws {
        let (presenter, mockTabShower, _) = createPresenter()
        let dialog = presenter.makeUpgradeDialog(source: .model)

        dialog.onHaveSubscription?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(!url.absoluteString.contains("featurePage"))
    }
}
