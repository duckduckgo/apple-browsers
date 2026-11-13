//
//  SubscriptionCancellationWideEventTests.swift
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

import Common
import Foundation
import Testing
@_spi(Testing) import PixelKit
@_spi(Testing) import WideEvent
@testable import Subscription
@testable import DuckDuckGo

@Suite("Subscription cancellation wide event")
struct SubscriptionCancellationWideEventTests {

    private struct TestError: Error {}

    private let tapDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let productId = "ddg.privacy.pro.monthly.renews.us"

    private func subscription(status: DuckDuckGoSubscription.Status,
                              platform: DuckDuckGoSubscription.Platform = .apple,
                              productId: String? = nil,
                              activeOffers: [DuckDuckGoSubscription.Offer] = []) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(productId: productId ?? self.productId,
                               name: "Test Subscription",
                               billingPeriod: .monthly,
                               startedAt: tapDate.addingTimeInterval(.days(-10)),
                               expiresOrRenewsAt: tapDate.addingTimeInterval(.days(20)),
                               platform: platform,
                               status: status,
                               activeOffers: activeOffers,
                               tier: nil,
                               availableChanges: nil,
                               pendingPlans: nil,
                               planCountry: nil)
    }

    private func makeData(start: Date? = nil) -> SubscriptionCancellationWideEventData {
        SubscriptionCancellationWideEventData(entryPoint: .cancelSubscription,
                                              purchasePlatform: .appStore,
                                              isTrial: false,
                                              subscriptionIdentifier: productId,
                                              daysSincePurchase: .d8To30,
                                              daysUntilRenewal: .d8To30,
                                              startDate: start ?? tapDate)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An entry tap on an auto-renewing subscription starts a flow with the tap's details", .timeLimit(.minutes(1)))
    func entryTapStartsFlow() throws {
        let wideEvent = WideEventMock()
        let instrumentation = SubscriptionCancellationInstrumentation(pixelFiring: nil, wideEvent: wideEvent, now: { tapDate })

        instrumentation.manageSubscriptionTapped(entryPoint: .managePaymentOrCancel,
                                                 subscription: subscription(status: .autoRenewable, platform: .stripe, activeOffers: [.init(type: .trial)]))

        let data = try #require(wideEvent.started.first as? SubscriptionCancellationWideEventData)
        #expect(wideEvent.started.count == 1)
        let parameters = data.jsonParameters()
        #expect(parameters["feature.data.ext.entry_point"] as? String == "manage_payment_or_cancel")
        #expect(parameters["feature.data.ext.purchase_platform"] as? String == "stripe")
        #expect(parameters["feature.data.ext.is_trial"] as? Bool == true)
        #expect(parameters["feature.data.ext.subscription_identifier"] as? String == productId)
        #expect(parameters["feature.data.ext.days_since_purchase_bucketed"] as? String == "d8_30")
        #expect(parameters["feature.data.ext.days_until_renewal_bucketed"] as? String == "d8_30")
        #expect(parameters.count == 6)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Tapping Cancel Subscription fires the click pixel and starts the wide event in one call", .timeLimit(.minutes(1)))
    func cancelSubscriptionTappedFiresPixelAndStartsWideEvent() throws {
        let pixelKit = PixelKitMock()
        let wideEvent = WideEventMock()

        SubscriptionCancellationInstrumentation(pixelFiring: pixelKit, wideEvent: wideEvent)
            .cancelSubscriptionTapped(subscription: subscription(status: .autoRenewable))

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationCancelClick, frequency: .standard)])
        let data = try #require(wideEvent.started.first as? SubscriptionCancellationWideEventData)
        #expect(data.entryPoint == .cancelSubscription)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No flow starts when the subscription isn't auto-renewing or isn't from the App Store or Stripe", .timeLimit(.minutes(1)), arguments: [
        (DuckDuckGoSubscription.Status.notAutoRenewable, DuckDuckGoSubscription.Platform.apple),
        (.expired, .apple),
        (.autoRenewable, .google),
        (.autoRenewable, .unknown)
    ])
    func ineligibleSubscriptionDoesNotStartFlow(status: DuckDuckGoSubscription.Status, platform: DuckDuckGoSubscription.Platform) {
        let wideEvent = WideEventMock()

        SubscriptionCancellationInstrumentation(pixelFiring: nil, wideEvent: wideEvent)
            .manageSubscriptionTapped(entryPoint: .manageSubscription, subscription: subscription(status: status, platform: platform))

        #expect(wideEvent.started.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A second entry tap while a flow is pending doesn't start another flow", .timeLimit(.minutes(1)))
    func secondTapDoesNotStartAnotherFlow() {
        let wideEvent = WideEventMock()
        let instrumentation = SubscriptionCancellationInstrumentation(pixelFiring: nil, wideEvent: wideEvent)

        instrumentation.cancelSubscriptionTapped(subscription: subscription(status: .autoRenewable))
        instrumentation.manageSubscriptionTapped(entryPoint: .manageSubscription, subscription: subscription(status: .autoRenewable))

        #expect(wideEvent.started.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @available(iOS 16, macOS 13, *)
    @Test("A failure that blocks cancelling completes the pending flow with FAILURE and the error", .timeLimit(.minutes(1)), arguments: [true, false])
    func blockingFailureCompletesWithFailure(isFlowLoadFailure: Bool) throws {
        let wideEvent = WideEventMock()
        let instrumentation = SubscriptionCancellationInstrumentation(pixelFiring: nil, wideEvent: wideEvent)
        instrumentation.cancelSubscriptionTapped(subscription: subscription(status: .autoRenewable))

        if isFlowLoadFailure {
            instrumentation.flowLoadFailed(TestError())
        } else {
            instrumentation.manageSubscriptionFailed(TestError())
        }

        let completion = try #require(wideEvent.completions.first)
        #expect(wideEvent.completions.count == 1)
        #expect(completion.1 == .failure)
        #expect((completion.0 as? SubscriptionCancellationWideEventData)?.errorData != nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Tapping an entry again after a failure starts a new flow", .timeLimit(.minutes(1)))
    func entryTapAfterFailureStartsNewFlow() {
        let wideEvent = WideEventMock()
        let instrumentation = SubscriptionCancellationInstrumentation(pixelFiring: nil, wideEvent: wideEvent)
        let renewing = subscription(status: .autoRenewable)
        instrumentation.cancelSubscriptionTapped(subscription: renewing)
        instrumentation.manageSubscriptionFailed(TestError())

        instrumentation.manageSubscriptionTapped(entryPoint: .manageSubscription, subscription: renewing)

        #expect(wideEvent.started.count == 2)
        #expect(wideEvent.getAllFlowData(SubscriptionCancellationWideEventData.self).count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A subscription no longer auto-renewing completes with SUCCESS auto_renew_disabled", .timeLimit(.minutes(1)))
    func autoRenewDisabledCompletesWithSuccess() {
        let decision = makeData().completionDecision(for: subscription(status: .notAutoRenewable), now: tapDate.addingTimeInterval(.minutes(2)))

        guard case .complete(.success(reason: "auto_renew_disabled")) = decision else {
            Issue.record("Unexpected decision \(decision)")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A refresh showing a different plan that still auto-renews completes as CANCELLED and sends plan_changed as the status reason", .timeLimit(.minutes(1)))
    func planChangeCompletesAsCancelledWithReason() {
        let data = makeData()
        let decision = data.completionDecision(for: subscription(status: .autoRenewable, productId: "ddg.privacy.pro.yearly.renews.us"),
                                               now: tapDate.addingTimeInterval(.minutes(5)))

        guard case .complete(.cancelled) = decision else {
            Issue.record("Unexpected decision \(decision)")
            return
        }
        #expect(data.jsonParameters()[WideEventParameter.Feature.statusReason] as? String == "plan_changed")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Outcomes other than a plan change don't add a status reason of their own", .timeLimit(.minutes(1)))
    func nonPlanChangeOutcomesLeaveStatusReasonToTheSender() {
        let data = makeData()
        _ = data.completionDecision(for: subscription(status: .notAutoRenewable), now: tapDate)

        #expect(data.jsonParameters()[WideEventParameter.Feature.statusReason] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A same-plan auto-renewing subscription stays pending before 24h and times out after", .timeLimit(.minutes(1)))
    func samePlanAutoRenewingTimesOutAfter24Hours() {
        let data = makeData()
        let renewing = subscription(status: .autoRenewable)

        guard case .keepPending = data.completionDecision(for: renewing, now: tapDate.addingTimeInterval(.hours(23))) else {
            Issue.record("Expected pending before 24h")
            return
        }
        guard case .complete(.unknown(reason: "timeout")) = data.completionDecision(for: renewing, now: tapDate.addingTimeInterval(.hours(24))) else {
            Issue.record("Expected timeout at 24h")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("No subscription completes with UNKNOWN no_subscription", .timeLimit(.minutes(1)))
    func missingSubscriptionCompletesWithNoSubscription() {
        let decision = makeData().completionDecision(for: nil, now: tapDate.addingTimeInterval(.minutes(1)))

        guard case .complete(.unknown(reason: "no_subscription")) = decision else {
            Issue.record("Unexpected decision \(decision)")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("An expired, inactive or unreadable subscription completes with UNKNOWN partial_data", .timeLimit(.minutes(1)), arguments: [
        DuckDuckGoSubscription.Status.expired,
        .inactive,
        .unknown
    ])
    func unusableSubscriptionCompletesWithPartialData(status: DuckDuckGoSubscription.Status) {
        let decision = makeData().completionDecision(for: subscription(status: status), now: tapDate.addingTimeInterval(.minutes(1)))

        guard case .complete(.unknown(reason: "partial_data")) = decision else {
            Issue.record("Unexpected decision \(decision)")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the App Store sheet after cancelling fires the cancelled pixel and leaves completing the wide event to the observer", .timeLimit(.minutes(1)))
    func manageSubscriptionClosedAfterCancellingFiresPixelOnly() {
        let pixelKit = PixelKitMock()
        let wideEvent = WideEventMock()
        let instrumentation = SubscriptionCancellationInstrumentation(pixelFiring: pixelKit, wideEvent: wideEvent, now: { tapDate })
        let before = subscription(status: .autoRenewable)
        instrumentation.cancelSubscriptionTapped(subscription: before)

        instrumentation.manageSubscriptionClosed(entry: .cancellation, subscriptionBefore: before, subscriptionAfter: subscription(status: .notAutoRenewable))

        #expect(pixelKit.actualFireCalls == [
            ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationCancelClick, frequency: .standard),
            ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationAppStoreCancelled(entry: .cancellation, isTrial: false, daysSincePurchase: .d8To30),
                             frequency: .standard)
        ])
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Closing the App Store sheet without cancelling fires no cancelled pixel and keeps the wide event pending", .timeLimit(.minutes(1)))
    func manageSubscriptionClosedWithoutCancellingKeepsWideEventPending() {
        let pixelKit = PixelKitMock()
        let wideEvent = WideEventMock()
        let instrumentation = SubscriptionCancellationInstrumentation(pixelFiring: pixelKit, wideEvent: wideEvent, now: { tapDate })
        let before = subscription(status: .autoRenewable)
        instrumentation.manageSubscriptionTapped(entryPoint: .manageSubscription, subscription: before)

        instrumentation.manageSubscriptionClosed(entry: .manage, subscriptionBefore: before, subscriptionAfter: before)

        #expect(pixelKit.actualFireCalls.isEmpty)
        #expect(wideEvent.completions.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("On launch, the flow stays pending before 24h and completes with timeout after", .timeLimit(.minutes(1)), arguments: [
        (1, String?.none),
        (25, "timeout")
    ])
    func launchUsesTimeoutOnly(hoursSinceTap: Int, expectedReason: String?) async {
        let data = makeData(start: Date().addingTimeInterval(.hours(-hoursSinceTap)))

        let decision = await data.completionDecision(for: .appLaunch)

        switch (decision, expectedReason) {
        case (.keepPending, nil):
            break
        case (.complete(.unknown(let reason)), let expected?) where reason == expected:
            break
        default:
            Issue.record("Expected \(expectedReason ?? "pending"), got \(decision)")
        }
    }

    private func subscriptionChange(_ subscription: DuckDuckGoSubscription?) -> Notification {
        Notification(name: .subscriptionDidChange,
                     object: nil,
                     userInfo: subscription.map { [UserDefaultsCacheKey.subscription: $0] })
    }

    private func makePendingObserver(notificationCenter: NotificationCenter = .default,
                                     fetcher: @escaping () async throws -> DuckDuckGoSubscription? = { nil })
    -> (WideEventMock, SubscriptionCancellationWideEventObserver) {
        let wideEvent = WideEventMock()
        wideEvent.startFlow(makeData())
        let observer = SubscriptionCancellationWideEventObserver(wideEvent: wideEvent,
                                                                 notificationCenter: notificationCenter,
                                                                 subscriptionFetcher: fetcher,
                                                                 now: { tapDate })
        return (wideEvent, observer)
    }

    enum FallbackFetch: CaseIterable {
        case cancelledSubscription, noSubscription, failure
    }

    @available(iOS 16, macOS 13, *)
    @Test("A subscription change payload decides the pending flow", .timeLimit(.minutes(1)), arguments: [
        (DuckDuckGoSubscription.Status.notAutoRenewable, false, [WideEventStatus.success(reason: "auto_renew_disabled")]),
        (.autoRenewable, true, [.cancelled]),
        (.autoRenewable, false, [])
    ])
    func subscriptionChangePayloadDecidesPendingFlow(status: DuckDuckGoSubscription.Status, planChanged: Bool, expectedStatuses: [WideEventStatus]) async {
        let (wideEvent, observer) = makePendingObserver()
        let changed = subscription(status: status, productId: planChanged ? "ddg.privacy.pro.yearly.renews.us" : nil)

        await observer.handleSubscriptionChange(subscriptionChange(changed))

        #expect(wideEvent.completions.map(\.1) == expectedStatuses)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A subscription change without a payload decides from the fallback fetch", .timeLimit(.minutes(1)), arguments: FallbackFetch.allCases)
    func subscriptionChangeWithoutPayloadUsesFallbackFetch(fetch: FallbackFetch) async {
        let cancelled = subscription(status: .notAutoRenewable)
        let (wideEvent, observer) = makePendingObserver(fetcher: {
            switch fetch {
            case .cancelledSubscription: return cancelled
            case .noSubscription: return nil
            case .failure: throw TestError()
            }
        })

        await observer.handleSubscriptionChange(subscriptionChange(nil))

        let expectedStatuses: [WideEventStatus] = switch fetch {
        case .cancelledSubscription: [.success(reason: "auto_renew_disabled")]
        case .noSubscription: [.unknown(reason: "no_subscription")]
        case .failure: []
        }
        #expect(wideEvent.completions.map(\.1) == expectedStatuses)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A posted subscription change reaches the observer once it starts observing", .timeLimit(.minutes(1)))
    func postedSubscriptionChangeCompletesPendingFlow() async {
        let notificationCenter = NotificationCenter()
        let (wideEvent, observer) = makePendingObserver(notificationCenter: notificationCenter)
        observer.startObservingSubscriptionChanges()

        let status = await withCheckedContinuation { continuation in
            wideEvent.onComplete = { _, status in continuation.resume(returning: status) }
            notificationCenter.post(subscriptionChange(subscription(status: .notAutoRenewable)))
        }

        #expect(status == .success(reason: "auto_renew_disabled"))
    }
}
