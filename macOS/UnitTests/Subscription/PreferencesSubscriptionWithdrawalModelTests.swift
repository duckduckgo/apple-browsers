//
//  PreferencesSubscriptionWithdrawalModelTests.swift
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
@testable import SubscriptionUI

@MainActor
@Suite("Preferences subscription withdrawal model")
final class PreferencesSubscriptionWithdrawalModelTests {

    private let subscriptionManager = SubscriptionManagerMock()
    private var isFeatureEnabled = true
    private var events: [String] = []
    private var openedURLs: [SubscriptionURL] = []
    private let stripeSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .stripe, tier: .plus)

    init() {
        subscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManager.getWithdrawalEligibilityResult = .success(Self.makeEligibility())
    }

    // MARK: - Eligibility

    @available(macOS 13, *)
    @Test("An eligible Stripe subscriber gets an offer with a formatted amount and deadline", .timeLimit(.minutes(1)))
    func eligibleStripeSubscriberGetsOffer() async {
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer?.eligibleUntil == Self.longDate(Date(timeIntervalSince1970: 1760950800)))
        #expect(model.offer?.refundAmount == "£9.99")
        #expect(model.offer?.tierName == "Plus")
    }

    @available(macOS 13, *)
    @Test("A missing deadline still shows the offer, without the deadline", .timeLimit(.minutes(1)))
    func missingDeadlineStillShowsOffer() async {
        subscriptionManager.getWithdrawalEligibilityResult = .success(Self.makeEligibility(eligibleUntil: nil))
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer != nil)
        #expect(model.offer?.eligibleUntil == nil)
    }

    @available(macOS 13, *)
    @Test("An ineligible subscriber gets no offer", .timeLimit(.minutes(1)))
    func ineligibleSubscriberGetsNoOffer() async {
        subscriptionManager.getWithdrawalEligibilityResult = .success(WithdrawalEligibility(eligible: false, reason: "trial"))
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer == nil)
    }

    @available(macOS 13, *)
    @Test("A non-Stripe subscriber does not fetch eligibility and gets no offer", .timeLimit(.minutes(1)), arguments: [
        DuckDuckGoSubscription.Platform.apple, .google
    ])
    func nonStripeSubscriberDoesNotFetch(platform: DuckDuckGoSubscription.Platform) async {
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: platform, tier: .plus)
        let model = makeModel()

        await model.fetchEligibility(for: subscription)

        #expect(model.eligibility == nil)
        #expect(model.offer == nil)
        #expect(events.isEmpty)
    }

    @available(macOS 13, *)
    @Test("With the flag off, eligibility is not fetched", .timeLimit(.minutes(1)))
    func flagOffDoesNotFetch() async {
        isFeatureEnabled = false
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.eligibility == nil)
        #expect(model.offer == nil)
        #expect(events.isEmpty)
    }

    @available(macOS 13, *)
    @Test("Turning the flag off after fetching hides the offer", .timeLimit(.minutes(1)))
    func flagTurnedOffHidesOffer() async {
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)
        #expect(model.offer != nil)

        isFeatureEnabled = false

        #expect(model.offer == nil)
    }

    @available(macOS 13, *)
    @Test("A signed-out user does not fetch eligibility or report a failure", .timeLimit(.minutes(1)))
    func signedOutUserDoesNotFetch() async {
        subscriptionManager.resultTokenContainer = nil
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.eligibility == nil)
        #expect(events.isEmpty)
    }

    @available(macOS 13, *)
    @Test("A failed eligibility fetch reports the failure and shows no offer", .timeLimit(.minutes(1)))
    func failedEligibilityFetchReportsFailure() async {
        subscriptionManager.getWithdrawalEligibilityResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.internalServerError))
        let model = makeModel()

        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer == nil)
        #expect(count("withdrawalEligibilityDidFail") == 1)
    }

    @available(macOS 13, *)
    @Test("A failed refetch hides an earlier offer", .timeLimit(.minutes(1)))
    func failedRefetchHidesEarlierOffer() async {
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)
        #expect(model.offer != nil)

        subscriptionManager.getWithdrawalEligibilityResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.internalServerError))
        await model.fetchEligibility(for: stripeSubscription)

        #expect(model.offer == nil)
    }

    // MARK: - Confirmation message

    @available(macOS 13, *)
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
        let features = listFormatter.string(from: [UserText.vpnServiceTitle,
                                                   UserText.personalInformationRemovalServiceTitle,
                                                   UserText.identityTheftRestorationServiceTitle,
                                                   UserText.paidAIChatTitle])!

        #expect(model.confirmationMessage(for: offer) == UserText.withdrawDialogMessage(tierName: "Plus", refundAmount: "£9.99")
                + "\n\n" + UserText.withdrawDialogFeaturesMessage(features: features))
    }

    @available(macOS 13, *)
    @Test("Without entitlements, the confirmation message omits the feature paragraph", .timeLimit(.minutes(1)))
    func confirmationMessageWithoutEntitlements() {
        let model = makeModel()
        let offer = SubscriptionWithdrawalOffer(eligibleUntil: nil, refundAmount: "£9.99", tierName: "Plus", entitlements: [])

        #expect(model.confirmationMessage(for: offer) == UserText.withdrawDialogMessage(tierName: "Plus", refundAmount: "£9.99"))
    }

    @available(macOS 13, *)
    @Test("Without a refund amount, the confirmation message uses the full-refund copy", .timeLimit(.minutes(1)))
    func confirmationMessageWithoutAmount() {
        let model = makeModel()
        let offer = SubscriptionWithdrawalOffer(eligibleUntil: nil, refundAmount: nil, tierName: "Plus", entitlements: [])

        #expect(model.confirmationMessage(for: offer) == UserText.withdrawDialogMessage(tierName: "Plus"))
    }

    // MARK: - Withdraw

    @available(macOS 13, *)
    @Test("A successful withdrawal returns the confirmation without signing out", .timeLimit(.minutes(1)))
    func successfulWithdrawalReturnsConfirmation() async {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(refundedAmount: "9.99",
                                                                                               currency: "EUR",
                                                                                               requestedAt: Date(timeIntervalSince1970: 1760950800)))
        let model = makeModel()

        await model.withdraw()

        #expect(model.confirmation == SubscriptionWithdrawalConfirmation(withdrawalDate: Self.longDate(Date(timeIntervalSince1970: 1760950800)),
                                                                         refundAmount: "€9.99"))
        #expect(!model.isWithdrawing)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(!model.isShowingError)
        #expect(events == ["didClickConfirmWithdrawal", "withdrawalDidStart", "withdrawalDidFinish"])
    }

    @available(macOS 13, *)
    @Test("A 409 hides the offer without an error dialog and reports the failure", .timeLimit(.minutes(1)))
    func conflictHidesOffer() async {
        subscriptionManager.withdrawSubscriptionResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.conflict))
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)
        #expect(model.offer != nil)

        await model.withdraw()

        #expect(model.confirmation == nil)
        #expect(model.offer == nil)
        #expect(!model.isShowingError)
        #expect(!model.isWithdrawing)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(count("withdrawalDidFinish") == 1)
        #expect(count("withdrawalDidFail") == 1)
    }

    @available(macOS 13, *)
    @Test("Any other failure shows the error dialog and reports the failure", .timeLimit(.minutes(1)))
    func otherFailureShowsError() async {
        subscriptionManager.withdrawSubscriptionResult = .failure(SubscriptionEndpointServiceError.invalidResponseCode(.internalServerError))
        let model = makeModel()

        await model.withdraw()

        #expect(model.confirmation == nil)
        #expect(model.isShowingError)
        #expect(!model.isWithdrawing)
        #expect(subscriptionManager.resultTokenContainer != nil)
        #expect(count("withdrawalDidFinish") == 1)
        #expect(count("withdrawalDidFail") == 1)
    }

    @available(macOS 13, *)
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
        #expect(count("withdrawalDidFail") == 0)
    }

    @available(macOS 13, *)
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

    @available(macOS 13, *)
    @Test("Without an amount from the response or eligibility, the confirmation has no refund amount", .timeLimit(.minutes(1)))
    func noAmountAnywhereHasNoRefundAmount() async throws {
        subscriptionManager.getWithdrawalEligibilityResult = .success(WithdrawalEligibility(eligible: true))
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse())
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)

        await model.withdraw()
        let confirmation = try #require(model.confirmation)

        #expect(confirmation.refundAmount == nil)
    }

    @available(macOS 13, *)
    @Test("A response amount without a currency falls back to the eligibility refund amount", .timeLimit(.minutes(1)))
    func responseAmountWithoutCurrencyUsesEligibilityAmount() async throws {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(refundedAmount: "5.00"))
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)

        await model.withdraw()
        let confirmation = try #require(model.confirmation)

        #expect(confirmation.refundAmount == "£9.99")
    }

    // MARK: - Completing the withdrawal

    @available(macOS 13, *)
    @Test("Completing after a withdrawal signs out and clears the withdrawn state", .timeLimit(.minutes(1)))
    func completeAfterWithdrawalSignsOut() async {
        subscriptionManager.withdrawSubscriptionResult = .success(WithdrawSubscriptionResponse(refundedAmount: "9.99", currency: "GBP"))
        let model = makeModel()
        await model.fetchEligibility(for: stripeSubscription)
        await model.withdraw()

        await model.completeWithdrawalIfNeeded()

        #expect(subscriptionManager.resultTokenContainer == nil)
        #expect(model.confirmation == nil)
        #expect(model.offer == nil)
    }

    @available(macOS 13, *)
    @Test("Completing without a withdrawal does not sign out", .timeLimit(.minutes(1)))
    func completeWithoutWithdrawalDoesNotSignOut() async {
        let model = makeModel()

        await model.completeWithdrawalIfNeeded()

        #expect(subscriptionManager.resultTokenContainer != nil)
    }

    // MARK: - Dialog

    @available(macOS 13, *)
    @Test("Clicking withdraw reports only the click", .timeLimit(.minutes(1)))
    func withdrawTappedReportsClick() {
        makeModel().withdrawTapped()

        #expect(events == ["didClickWithdraw"])
    }

    @available(macOS 13, *)
    @Test("Showing the confirmation dialog reports the dialog shown", .timeLimit(.minutes(1)))
    func confirmationShownReportsDialogShown() {
        makeModel().confirmationShown()

        #expect(events == ["didShowWithdrawalDialog"])
    }

    @available(macOS 13, *)
    @Test("Keeping the subscription reports the keep click only", .timeLimit(.minutes(1)))
    func keepTappedReportsKeep() {
        makeModel().keepTapped()

        #expect(events == ["didClickKeepSubscription"])
    }

    @available(macOS 13, *)
    @Test("Opening the help page opens the cancel or change subscription help page", .timeLimit(.minutes(1)))
    func openHelpPageOpensHelpPage() {
        makeModel().openHelpPage()

        #expect(events == ["openURL"])
        #expect(openedURLs == [.helpPagesCancelOrChangeSubscription])
    }

    // MARK: - Helpers

    private func makeModel() -> PreferencesSubscriptionWithdrawalModel {
        PreferencesSubscriptionWithdrawalModel(subscriptionManager: subscriptionManager,
                                               isFeatureEnabled: { [unowned self] in self.isFeatureEnabled },
                                               locale: Locale(identifier: "en_US"),
                                               userEventHandler: { [unowned self] event in
            if case .openURL(let url) = event {
                self.openedURLs.append(url)
            }
            self.events.append(String(describing: event).components(separatedBy: "(")[0])
        })
    }

    private func count(_ event: String) -> Int {
        events.filter { $0 == event }.count
    }

    private static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func makeEligibility(eligibleUntil: Date? = Date(timeIntervalSince1970: 1760950800)) -> WithdrawalEligibility {
        WithdrawalEligibility(eligible: true, eligibleUntil: eligibleUntil, refundAmount: "9.99", refundCurrency: "GBP")
    }
}
