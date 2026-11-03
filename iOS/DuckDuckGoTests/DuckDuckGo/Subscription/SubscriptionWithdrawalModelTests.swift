//
//  SubscriptionWithdrawalModelTests.swift
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
@Suite("Subscription withdrawal model")
struct SubscriptionWithdrawalModelTests {

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
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        let offer = model.offer(for: stripeSubscription)
        #expect(offer?.eligibleUntil != nil)
        #expect(offer?.refundAmount == "£9.99")
        #expect(offer?.tierName == "Plus")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A missing deadline still shows the offer, without the deadline", .timeLimit(.minutes(1)))
    func missingDeadlineStillShowsOffer() async {
        subscriptionManager.getWithdrawalEligibilityResult = .success(Self.makeEligibility(eligibleUntil: nil))
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer(for: stripeSubscription) != nil)
        #expect(model.offer(for: stripeSubscription)?.eligibleUntil == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An ineligible subscriber gets no offer", .timeLimit(.minutes(1)))
    func ineligibleSubscriberGetsNoOffer() async {
        subscriptionManager.getWithdrawalEligibilityResult = .success(WithdrawalEligibility(eligible: false, reason: "trial"))
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer(for: stripeSubscription) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A non-Stripe subscriber does not fetch eligibility and gets no offer", .timeLimit(.minutes(1)), arguments: [
        DuckDuckGoSubscription.Platform.apple, .google
    ])
    func nonStripeSubscriberDoesNotFetch(platform: DuckDuckGoSubscription.Platform) async {
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: platform, tier: .plus)
        let model = makeModel()

        await model.fetchEligibility(for: subscription)

        #expect(model.eligibility == nil)
        #expect(model.offer(for: subscription) == nil)
        #expect(instrumentation.eligibilityFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the flag off, eligibility is not fetched", .timeLimit(.minutes(1)))
    func flagOffDoesNotFetch() async {
        featureFlagger.enabledFeatureFlags = []
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.eligibility == nil)
        #expect(model.offer(for: stripeSubscription) == nil)
        #expect(instrumentation.eligibilityFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A signed-out user does not fetch eligibility or fire the failure pixel", .timeLimit(.minutes(1)))
    func signedOutUserDoesNotFetch() async {
        subscriptionManager.resultTokenContainer = nil
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.eligibility == nil)
        #expect(instrumentation.eligibilityFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed eligibility fetch fires the eligibility failure pixel and shows no offer", .timeLimit(.minutes(1)))
    func failedEligibilityFetchFiresPixel() async {
        subscriptionManager.getWithdrawalEligibilityResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.internalServerError))
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer(for: stripeSubscription) == nil)
        #expect(instrumentation.eligibilityFailures.count == 1)
    }

    // MARK: - Confirmation message

    @available(iOS 16, macOS 13, *)
    @Test("The confirmation message lists each feature once, in order", .timeLimit(.minutes(1)))
    func confirmationMessageListsFeaturesOnceInOrder() {
        let model = makeModel()
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

        #expect(model.confirmationMessage(for: offer) == UserText.subscriptionWithdrawConfirmMessage(tierName: "Plus", refundAmount: "£9.99")
                + "\n\n" + UserText.subscriptionWithdrawConfirmFeaturesMessage(features: features))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without entitlements, the confirmation message omits the feature paragraph", .timeLimit(.minutes(1)))
    func confirmationMessageWithoutEntitlements() {
        let model = makeModel()
        let offer = SubscriptionWithdrawalOffer(eligibleUntil: nil, refundAmount: "£9.99", tierName: "Plus", entitlements: [])

        #expect(model.confirmationMessage(for: offer) == UserText.subscriptionWithdrawConfirmMessage(tierName: "Plus", refundAmount: "£9.99"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without a refund amount, the confirmation message uses the full-refund copy", .timeLimit(.minutes(1)))
    func confirmationMessageWithoutAmount() {
        let model = makeModel()
        let offer = SubscriptionWithdrawalOffer(eligibleUntil: nil, refundAmount: nil, tierName: "Plus", entitlements: [])

        #expect(model.confirmationMessage(for: offer) == UserText.subscriptionWithdrawConfirmMessage(tierName: "Plus"))
    }

    // MARK: - Withdraw

    @available(iOS 16, macOS 13, *)
    @Test("A successful withdrawal returns the confirmation without signing out", .timeLimit(.minutes(1)))
    func successfulWithdrawalReturnsConfirmation() async {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(refundedAmount: "9.99",
                                                                                               currency: "EUR",
                                                                                               requestedAt: Date(timeIntervalSince1970: 1760950800)))
        let model = makeModel()

        await model.withdraw()
        let confirmation = model.confirmation

        #expect(confirmation?.refundAmount == "€9.99")
        #expect(!model.isWithdrawing)
        #expect(confirmation?.withdrawalDate.isEmpty == false)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(!model.isShowingError)
        #expect(instrumentation.confirmClickedCount == 1)
        #expect(instrumentation.withdrawalFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A 409 hides the offer without an error alert and fires the failure pixel", .timeLimit(.minutes(1)))
    func conflictHidesOffer() async {
        subscriptionManager.withdrawSubscriptionResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.conflict))
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)
        #expect(model.offer(for: stripeSubscription) != nil)

        await model.withdraw()
        let confirmation = model.confirmation

        #expect(confirmation == nil)
        #expect(model.offer(for: stripeSubscription) == nil)
        #expect(!model.isShowingError)
        #expect(!model.isWithdrawing)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(instrumentation.withdrawalFailures.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Any other failure shows the error alert and fires the failure pixel", .timeLimit(.minutes(1)))
    func otherFailureShowsError() async {
        subscriptionManager.withdrawSubscriptionResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.internalServerError))
        let model = makeModel()

        await model.withdraw()
        let confirmation = model.confirmation

        #expect(confirmation == nil)
        #expect(model.isShowingError)
        #expect(!model.isWithdrawing)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(instrumentation.withdrawalFailures.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A success whose response cannot be decoded still completes, using the eligibility refund amount and today", .timeLimit(.minutes(1)))
    func undecodableSuccessStillCompletes() async throws {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse())
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)

        await model.withdraw()
        let confirmation = try #require(model.confirmation)

        #expect(confirmation.refundAmount == "£9.99")
        #expect(confirmation.withdrawalDate == Self.longDate(Date()))
        #expect(!model.isShowingError)
        #expect(!model.isWithdrawing)
        #expect(instrumentation.withdrawalFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A response with a date but no amount shows the date and the eligibility refund amount", .timeLimit(.minutes(1)))
    func responseWithoutAmountUsesEligibilityAmount() async throws {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(requestedAt: Date(timeIntervalSince1970: 1760950800)))
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)

        await model.withdraw()
        let confirmation = try #require(model.confirmation)

        #expect(confirmation.withdrawalDate == Self.longDate(Date(timeIntervalSince1970: 1760950800)))
        #expect(confirmation.refundAmount == "£9.99")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without an amount from the response or eligibility, the confirmation has no refund amount", .timeLimit(.minutes(1)))
    func noAmountAnywhereHasNoRefundAmount() async throws {
        subscriptionManager.getWithdrawalEligibilityResult = .success(WithdrawalEligibility(eligible: true))
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse())
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)

        await model.withdraw()
        let confirmation = try #require(model.confirmation)

        #expect(confirmation.refundAmount == nil)
        #expect(confirmation.withdrawalDate == Self.longDate(Date()))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A response amount without a currency falls back to the eligibility refund amount", .timeLimit(.minutes(1)))
    func responseAmountWithoutCurrencyUsesEligibilityAmount() async throws {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(refundedAmount: "5.00"))
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)

        await model.withdraw()
        let confirmation = try #require(model.confirmation)

        #expect(confirmation.refundAmount == "£9.99")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without an amount and currency from the same source, the confirmation has no refund amount", .timeLimit(.minutes(1)))
    func missingCurrencyEverywhereHasNoRefundAmount() async throws {
        subscriptionManager.getWithdrawalEligibilityResult = .success(WithdrawalEligibility(eligible: true, refundAmount: "9.99"))
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(refundedAmount: "9.99"))
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)

        await model.withdraw()
        let confirmation = try #require(model.confirmation)

        #expect(confirmation.refundAmount == nil)
    }

    // MARK: - Dialog

    @available(iOS 16, macOS 13, *)
    @Test("Tapping the row fires only the click pixel", .timeLimit(.minutes(1)))
    func withdrawTappedFiresClickPixel() {
        makeModel().withdrawTapped()

        #expect(instrumentation.withdrawClickedCount == 1)
        #expect(instrumentation.dialogShownCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Showing the confirmation dialog fires the dialog shown pixel", .timeLimit(.minutes(1)))
    func confirmationShownFiresPixel() {
        makeModel().confirmationShown()

        #expect(instrumentation.dialogShownCount == 1)
        #expect(instrumentation.withdrawClickedCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keeping the subscription fires the keep pixel only", .timeLimit(.minutes(1)))
    func keepTappedFiresPixel() {
        makeModel().keepTapped()

        #expect(instrumentation.keepClickedCount == 1)
        #expect(instrumentation.confirmClickedCount == 0)
    }

    // MARK: - Helpers

    private func makeModel() -> SubscriptionWithdrawalModel {
        SubscriptionWithdrawalModel(subscriptionManager: subscriptionManager,
                                    featureFlagger: featureFlagger,
                                    locale: Locale(identifier: "en_US"),
                                    instrumentation: instrumentation,
                                    urlOpener: MockURLOpener())
    }

    private static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func makeEligibility(eligibleUntil: Date? = Date(timeIntervalSince1970: 1760950800)) -> WithdrawalEligibility {
        WithdrawalEligibility(eligible: true, eligibleUntil: eligibleUntil, refundAmount: "9.99", refundCurrency: "GBP")
    }
}
