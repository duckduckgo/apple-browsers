//
//  SubscriptionWithdrawalFlowModelTests.swift
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
import Testing
@_spi(Testing) import Networking
@testable import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

@MainActor
@Suite("Subscription withdrawal flow model")
struct SubscriptionWithdrawalFlowModelTests {

    private let subscriptionManager = SubscriptionManagerMock()
    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.stripeInternationalSubscriptionWithdrawal])
    private let instrumentation = SubscriptionWithdrawalInstrumentationSpy()
    private let stripeSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .stripe, tier: .plus)

    init() {
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManager.getWithdrawalEligibilityResult = .success(Self.makeEligibility())
    }

    // MARK: - Eligibility

    @available(iOS 16, macOS 13, *)
    @Test("An eligible Stripe subscriber gets an offer with a formatted amount and deadline", .timeLimit(.minutes(1)))
    func eligibleStripeSubscriberGetsOffer() async {
        let flow = makeFlow()

        await flow.fetchEligibility()

        let offer = flow.offer(for: stripeSubscription)
        #expect(offer?.eligibleUntil != nil)
        #expect(offer?.refundAmount == "£9.99")
        #expect(offer?.tierName == "Plus")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A missing deadline still shows the offer, without the deadline", .timeLimit(.minutes(1)))
    func missingDeadlineStillShowsOffer() async {
        subscriptionManager.getWithdrawalEligibilityResult = .success(Self.makeEligibility(eligibleUntil: nil))
        let flow = makeFlow()

        await flow.fetchEligibility()

        #expect(flow.offer(for: stripeSubscription) != nil)
        #expect(flow.offer(for: stripeSubscription)?.eligibleUntil == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An ineligible subscriber gets no offer", .timeLimit(.minutes(1)))
    func ineligibleSubscriberGetsNoOffer() async {
        subscriptionManager.getWithdrawalEligibilityResult = .success(WithdrawalEligibility(eligible: false, reason: "trial"))
        let flow = makeFlow()

        await flow.fetchEligibility()

        #expect(flow.offer(for: stripeSubscription) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A non-Stripe subscriber gets no offer", .timeLimit(.minutes(1)))
    func nonStripeSubscriberGetsNoOffer() async {
        let flow = makeFlow()

        await flow.fetchEligibility()

        #expect(flow.offer(for: SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple, tier: .plus)) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off, eligibility is not fetched", .timeLimit(.minutes(1)))
    func flagOffDoesNotFetch() async {
        featureFlagger.enabledFeatureFlags = []
        let flow = makeFlow()

        await flow.fetchEligibility()

        #expect(flow.eligibility == nil)
        #expect(flow.offer(for: stripeSubscription) == nil)
        #expect(instrumentation.eligibilityFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A signed-out user does not fetch eligibility or fire the failure pixel", .timeLimit(.minutes(1)))
    func signedOutUserDoesNotFetch() async {
        subscriptionManager.resultTokenContainer = nil
        let flow = makeFlow()

        await flow.fetchEligibility()

        #expect(flow.eligibility == nil)
        #expect(instrumentation.eligibilityFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed eligibility fetch fires the eligibility failure pixel and shows no offer", .timeLimit(.minutes(1)))
    func failedEligibilityFetchFiresPixel() async {
        subscriptionManager.getWithdrawalEligibilityResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.internalServerError))
        let flow = makeFlow()

        await flow.fetchEligibility()

        #expect(flow.offer(for: stripeSubscription) == nil)
        #expect(instrumentation.eligibilityFailures.count == 1)
    }

    // MARK: - Confirmation message

    @available(iOS 16, macOS 13, *)
    @Test("The confirmation message lists each feature once, in order", .timeLimit(.minutes(1)))
    func confirmationMessageListsFeaturesOnceInOrder() {
        let flow = makeFlow()
        let offer = SubscriptionWithdrawalOffer(eligibleUntil: nil,
                                                refundAmount: "£9.99",
                                                tierName: "Plus",
                                                entitlements: [.paidAIChat, .identityTheftRestorationGlobal, .networkProtection,
                                                               .identityTheftRestoration, .dataBrokerProtection, .unknown])
        let listFormatter = ListFormatter()
        listFormatter.locale = Locale(identifier: "en_US")
        let features = listFormatter.string(from: [UserText.settingsPProVPNTitle,
                                                   UserText.settingsPProDBPTitle,
                                                   UserText.settingsPProITRTitle,
                                                   UserText.settingsSubscriptionAiChatTitle])!

        #expect(flow.confirmationMessage(for: offer) == UserText.subscriptionWithdrawConfirmMessage(tierName: "Plus", refundAmount: "£9.99")
                + "\n\n" + UserText.subscriptionWithdrawConfirmFeaturesMessage(features: features))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without entitlements, the confirmation message omits the feature paragraph", .timeLimit(.minutes(1)))
    func confirmationMessageWithoutEntitlements() {
        let flow = makeFlow()
        let offer = SubscriptionWithdrawalOffer(eligibleUntil: nil, refundAmount: "£9.99", tierName: "Plus", entitlements: [])

        #expect(flow.confirmationMessage(for: offer) == UserText.subscriptionWithdrawConfirmMessage(tierName: "Plus", refundAmount: "£9.99"))
    }

    // MARK: - Withdraw

    @available(iOS 16, macOS 13, *)
    @Test("A successful withdrawal returns the confirmation and signs out", .timeLimit(.minutes(1)))
    func successfulWithdrawalSignsOut() async {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(refundedAmount: "9.99",
                                                                                               currency: "EUR",
                                                                                               requestedAt: Date(timeIntervalSince1970: 1760950800)))
        let flow = makeFlow()

        let confirmation = await flow.withdraw()

        #expect(confirmation?.refundAmount == "€9.99")
        #expect(confirmation?.withdrawalDate.isEmpty == false)
        #expect(subscriptionManager.resultTokenContainer == nil)
        #expect(!flow.isShowingError)
        #expect(instrumentation.confirmClickedCount == 1)
        #expect(instrumentation.withdrawalFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A 409 hides the offer without an error alert and fires the failure pixel", .timeLimit(.minutes(1)))
    func conflictHidesOffer() async {
        subscriptionManager.withdrawSubscriptionResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.conflict))
        let flow = makeFlow()
        await flow.fetchEligibility()
        #expect(flow.offer(for: stripeSubscription) != nil)

        let confirmation = await flow.withdraw()

        #expect(confirmation == nil)
        #expect(flow.offer(for: stripeSubscription) == nil)
        #expect(!flow.isShowingError)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(instrumentation.withdrawalFailures.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Any other failure shows the error alert and fires the failure pixel", .timeLimit(.minutes(1)), arguments: [
        SubscriptionEndpointServiceError.invalidResponseCode(.internalServerError) as Error,
        DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid refundedAmount")) as Error
    ])
    func otherFailureShowsError(error: Error) async {
        subscriptionManager.withdrawSubscriptionResult = .failure(error)
        let flow = makeFlow()

        let confirmation = await flow.withdraw()

        #expect(confirmation == nil)
        #expect(flow.isShowingError)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(instrumentation.withdrawalFailures.count == 1)
    }

    // MARK: - Dialog

    @available(iOS 16, macOS 13, *)
    @Test("Tapping the row fires the click and dialog shown pixels", .timeLimit(.minutes(1)))
    func withdrawTappedFiresPixels() {
        makeFlow().withdrawTapped()

        #expect(instrumentation.withdrawClickedCount == 1)
        #expect(instrumentation.dialogShownCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keeping the subscription fires the keep pixel only", .timeLimit(.minutes(1)))
    func keepTappedFiresPixel() {
        makeFlow().keepTapped()

        #expect(instrumentation.keepClickedCount == 1)
        #expect(instrumentation.confirmClickedCount == 0)
    }

    // MARK: - Helpers

    private func makeFlow() -> SubscriptionWithdrawalFlowModel {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        return SubscriptionWithdrawalFlowModel(subscriptionManager: subscriptionManager,
                                               featureFlagger: featureFlagger,
                                               locale: Locale(identifier: "en_US"),
                                               dateFormatter: dateFormatter,
                                               instrumentation: instrumentation,
                                               openURL: { _ in })
    }

    private static func makeEligibility(eligibleUntil: Date? = Date(timeIntervalSince1970: 1760950800)) -> WithdrawalEligibility {
        WithdrawalEligibility(eligible: true, eligibleUntil: eligibleUntil, refundAmount: "9.99", refundCurrency: "GBP")
    }
}
