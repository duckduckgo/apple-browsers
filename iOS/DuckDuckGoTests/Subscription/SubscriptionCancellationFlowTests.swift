//
//  SubscriptionCancellationFlowTests.swift
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

import Combine
import Foundation
import Testing
@_spi(Testing) import PixelKit
import Networking
@testable import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

@Suite("Subscription cancellation flow eligibility")
struct SubscriptionCancellationFlowEligibilityTests {

    private let enUS = Locale(identifier: "en_US")

    @available(iOS 16, macOS 13, *)
    @Test("An auto-renewing Apple subscription in en_US with the flag on is eligible", .timeLimit(.minutes(1)))
    func autoRenewingAppleSubscriptionIsEligible() {
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple)

        #expect(SubscriptionCancellationFlowEligibility.isEligible(subscription: subscription, isFeatureEnabled: true, locale: enUS))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A trial Apple subscription is eligible", .timeLimit(.minutes(1)))
    func trialAppleSubscriptionIsEligible() {
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable,
                                                                platform: .apple,
                                                                activeOffers: [DuckDuckGoSubscription.Offer(type: .trial)])

        #expect(subscription.hasActiveTrialOffer)
        #expect(SubscriptionCancellationFlowEligibility.isEligible(subscription: subscription, isFeatureEnabled: true, locale: enUS))
    }

    @available(iOS 16, macOS 13, *)
    @Test("The flag being off makes an otherwise eligible subscription ineligible", .timeLimit(.minutes(1)))
    func flagOffIsIneligible() {
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple)

        #expect(!SubscriptionCancellationFlowEligibility.isEligible(subscription: subscription, isFeatureEnabled: false, locale: enUS))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Non-Apple platforms are ineligible", .timeLimit(.minutes(1)), arguments: [
        DuckDuckGoSubscription.Platform.stripe,
        .google,
        .unknown
    ])
    func nonApplePlatformsAreIneligible(platform: DuckDuckGoSubscription.Platform) {
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: platform)

        #expect(!SubscriptionCancellationFlowEligibility.isEligible(subscription: subscription, isFeatureEnabled: true, locale: enUS))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Subscriptions that are not auto-renewing are ineligible", .timeLimit(.minutes(1)), arguments: [
        DuckDuckGoSubscription.Status.notAutoRenewable,
        .gracePeriod,
        .inactive,
        .expired,
        .unknown
    ])
    func nonAutoRenewingSubscriptionsAreIneligible(status: DuckDuckGoSubscription.Status) {
        let subscription = SubscriptionMockFactory.subscription(status: status, platform: .apple)

        #expect(!SubscriptionCancellationFlowEligibility.isEligible(subscription: subscription, isFeatureEnabled: true, locale: enUS))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Locales other than en_US are ineligible", .timeLimit(.minutes(1)), arguments: [
        "en_GB",
        "es_US",
        "de_DE",
        "en"
    ])
    func nonEnglishUSLocalesAreIneligible(identifier: String) {
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple)

        #expect(!SubscriptionCancellationFlowEligibility.isEligible(subscription: subscription,
                                                                    isFeatureEnabled: true,
                                                                    locale: Locale(identifier: identifier)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("No subscription is ineligible", .timeLimit(.minutes(1)))
    func missingSubscriptionIsIneligible() {
        #expect(!SubscriptionCancellationFlowEligibility.isEligible(subscription: nil, isFeatureEnabled: true, locale: enUS))
    }
}

@Suite("Subscription cancellation flow feature info mapping")
struct SubscriptionCancellationFeatureInfoMappingTests {

    @available(iOS 16, macOS 13, *)
    @Test("Each known entitlement maps to its checklist item", .timeLimit(.minutes(1)), arguments: [
        (SubscriptionEntitlement.networkProtection, SubscriptionOnboardingChecklistItem.vpn),
        (.identityTheftRestoration, .idtr),
        (.identityTheftRestorationGlobal, .idtr),
        (.dataBrokerProtection, .pir),
        (.paidAIChat, .duckAI)
    ])
    func knownEntitlementsMap(entitlement: SubscriptionEntitlement, expected: SubscriptionOnboardingChecklistItem) {
        #expect(SubscriptionOnboardingChecklistItem(entitlement: entitlement) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unknown entitlement maps to nothing", .timeLimit(.minutes(1)))
    func unknownEntitlementMapsToNil() {
        #expect(SubscriptionOnboardingChecklistItem(entitlement: .unknown) == nil)
    }
}

@MainActor
@Suite("Subscription cancellation flow model")
struct SubscriptionCancellationFlowModelTests {

    private struct TestError: Error {}

    private let navigationErrors = PassthroughSubject<Error?, Never>()
    private let instrumentation = SubscriptionCancellationInstrumentationSpy()

    private func makeModel(onRequestStoreCancellation: @escaping () -> Void = {},
                           onClose: @escaping () -> Void = {}) -> SubscriptionCancellationFlowModel {
        SubscriptionCancellationFlowModel(navigationErrors: navigationErrors.eraseToAnyPublisher(),
                                          instrumentation: instrumentation,
                                          onRequestStoreCancellation: onRequestStoreCancellation,
                                          onClose: onClose)
    }

    @available(iOS 16, macOS 13, *)
    @Test("showFeatureInfo with a known entitlement presents its info sheet", .timeLimit(.minutes(1)))
    func showFeatureInfoPresentsSheet() {
        let model = makeModel()

        model.showFeatureInfo(for: .networkProtection)

        #expect(model.featureInfoItem == .vpn)
        #expect(instrumentation.featureInfoFailedCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("showFeatureInfo with an unknown entitlement fires the error pixel and presents nothing", .timeLimit(.minutes(1)))
    func showFeatureInfoWithUnknownEntitlementFails() {
        let model = makeModel()

        model.showFeatureInfo(for: .unknown)

        #expect(model.featureInfoItem == nil)
        #expect(instrumentation.featureInfoFailedCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("showFeatureInfo while a sheet is already presented is ignored", .timeLimit(.minutes(1)))
    func showFeatureInfoWhilePresentingIsIgnored() {
        let model = makeModel()

        model.showFeatureInfo(for: .networkProtection)
        model.showFeatureInfo(for: .paidAIChat)

        #expect(model.featureInfoItem == .vpn)
    }

    @available(iOS 16, macOS 13, *)
    @Test("showFeatureInfo after the sheet is closed presents the new sheet", .timeLimit(.minutes(1)))
    func showFeatureInfoAfterCloseIsPresented() {
        let model = makeModel()

        model.showFeatureInfo(for: .networkProtection)
        model.featureInfoItem = nil
        model.showFeatureInfo(for: .paidAIChat)

        #expect(model.featureInfoItem == .duckAI)
    }

    @available(iOS 16, macOS 13, *)
    @Test("requestStoreCancellation asks to open the store cancellation and closes the flow, once", .timeLimit(.minutes(1)))
    func requestStoreCancellationRequestsOnce() {
        var requestCount = 0
        var closeCount = 0
        let model = makeModel(onRequestStoreCancellation: { requestCount += 1 }, onClose: { closeCount += 1 })

        model.requestStoreCancellation()
        model.requestStoreCancellation()

        #expect(requestCount == 1)
        #expect(closeCount == 1)
        #expect(instrumentation.flowLoadFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page load failure fires the error pixel and queues the store cancellation without closing the flow", .timeLimit(.minutes(1)))
    func loadFailureFallsBackToStore() {
        var requestCount = 0
        var closeCount = 0
        let model = makeModel(onRequestStoreCancellation: { requestCount += 1 }, onClose: { closeCount += 1 })

        navigationErrors.send(TestError())

        #expect(requestCount == 1)
        #expect(closeCount == 0)
        #expect(instrumentation.flowLoadFailures.count == 1)
        withExtendedLifetime(model) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cleared navigation error does nothing", .timeLimit(.minutes(1)))
    func clearedNavigationErrorIsIgnored() {
        var requestCount = 0
        let model = makeModel { requestCount += 1 }

        navigationErrors.send(nil)

        #expect(requestCount == 0)
        #expect(instrumentation.flowLoadFailures.isEmpty)
        withExtendedLifetime(model) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("Repeated load failures fall back only once", .timeLimit(.minutes(1)))
    func repeatedLoadFailuresFallBackOnce() {
        var requestCount = 0
        let model = makeModel { requestCount += 1 }

        navigationErrors.send(TestError())
        navigationErrors.send(TestError())

        #expect(requestCount == 1)
        #expect(instrumentation.flowLoadFailures.count == 1)
        withExtendedLifetime(model) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("A load failure after cancellation was requested is not reported", .timeLimit(.minutes(1)))
    func loadFailureAfterRequestIsIgnored() {
        var requestCount = 0
        let model = makeModel { requestCount += 1 }

        model.requestStoreCancellation()
        navigationErrors.send(TestError())

        #expect(requestCount == 1)
        #expect(instrumentation.flowLoadFailures.isEmpty)
    }
}

@Suite("Subscription cancellation instrumentation")
struct SubscriptionCancellationInstrumentationTests {

    private struct TestError: Error {}

    @available(iOS 16, macOS 13, *)
    @Test("Tapping Cancel Subscription fires the click pixel", .timeLimit(.minutes(1)))
    func cancelClickedFiresPixel() {
        let pixelKit = PixelKitMock()

        SubscriptionCancellationInstrumentation(pixelFiring: pixelKit).cancelClicked()

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationCancelClick, frequency: .standard)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A detected cancellation fires the cancelled pixel with the platform", .timeLimit(.minutes(1)), arguments: [
        (DuckDuckGoSubscription.Platform.apple, "apple"),
        (.google, "google"),
        (.stripe, "stripe"),
        (.unknown, "unknown")
    ])
    func subscriptionCancelledFiresPixel(platform: DuckDuckGoSubscription.Platform, expectedValue: String) {
        let pixelKit = PixelKitMock()

        SubscriptionCancellationInstrumentation(pixelFiring: pixelKit).subscriptionCancelled(platform: platform)

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationSubscriptionCancelled(platform: platform), frequency: .standard)])
        #expect(SubscriptionPixel.subscriptionCancellationSubscriptionCancelled(platform: platform).parameters == ["platform": expectedValue])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page load failure fires the load failure pixel daily and count", .timeLimit(.minutes(1)))
    func flowLoadFailedFiresPixel() {
        let pixelKit = PixelKitMock()
        let error = TestError()

        SubscriptionCancellationInstrumentation(pixelFiring: pixelKit).flowLoadFailed(error)

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationFlowLoadFailure(error), frequency: .dailyAndCount)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A feature info failure fires the feature info failure pixel daily and count", .timeLimit(.minutes(1)))
    func featureInfoFailedFiresPixel() {
        let pixelKit = PixelKitMock()

        SubscriptionCancellationInstrumentation(pixelFiring: pixelKit).featureInfoFailed()

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationFeatureInfoFailure, frequency: .dailyAndCount)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pixel names match their definitions", .timeLimit(.minutes(1)))
    func pixelNames() {
        #expect(SubscriptionPixel.subscriptionCancellationCancelClick.name == "subscription_cancellation_cancel_click")
        #expect(SubscriptionPixel.subscriptionCancellationSubscriptionCancelled(platform: .apple).name == "subscription_cancellation_subscription_cancelled")
        #expect(SubscriptionPixel.subscriptionCancellationFlowLoadFailure(TestError()).name == "subscription_cancellation_flow_load_failure")
        #expect(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure.name == "subscription_cancellation_feature-info_failure")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancellation pixels use the standard platform suffix their definitions declare", .timeLimit(.minutes(1)))
    func cancellationPixelsUseStandardPlatformSuffix() {
        #expect(SubscriptionPixel.subscriptionCancellationCancelClick.platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionCancellationSubscriptionCancelled(platform: .apple).platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionCancellationFlowLoadFailure(TestError()).platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure.platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionActive.platformSuffixPolicy == .legacyOmitted)
    }
}
