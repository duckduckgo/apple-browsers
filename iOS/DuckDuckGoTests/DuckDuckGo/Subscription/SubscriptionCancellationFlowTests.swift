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
@testable import DuckDuckGo

@Suite("Subscription cancellation flow feature info mapping")
struct SubscriptionCancellationFeatureInfoMappingTests {

    @available(iOS 16, macOS 13, *)
    @Test("Each known entitlement maps to its info sheet's checklist item", .timeLimit(.minutes(1)), arguments: [
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

    private func makeModel(onOpenStoreCancellation: @escaping (Bool) -> Void = { _ in }) -> SubscriptionCancellationFlowModel {
        SubscriptionCancellationFlowModel(navigationErrors: navigationErrors.eraseToAnyPublisher(),
                                          instrumentation: instrumentation,
                                          onOpenStoreCancellation: onOpenStoreCancellation)
    }

    @available(iOS 16, macOS 13, *)
    @Test("showFeatureInfo with a known entitlement presents its info sheet", .timeLimit(.minutes(1)))
    func showFeatureInfoWithKnownEntitlementPresentsSheet() {
        var storeCancellationCalls: [Bool] = []
        let model = makeModel { storeCancellationCalls.append($0) }

        model.showFeatureInfo(for: .identityTheftRestorationGlobal)

        #expect(model.featureInfoItem == .idtr)
        #expect(instrumentation.featureInfoFailures.isEmpty)
        #expect(storeCancellationCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("showFeatureInfo with an unknown entitlement fires the error pixel and presents nothing", .timeLimit(.minutes(1)))
    func showFeatureInfoWithUnknownEntitlementFails() {
        var storeCancellationCalls: [Bool] = []
        let model = makeModel { storeCancellationCalls.append($0) }

        model.showFeatureInfo(for: .unknown)

        #expect(model.featureInfoItem == nil)
        #expect(instrumentation.featureInfoFailures == [.unknown])
        #expect(storeCancellationCalls.isEmpty)
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
    @Test("requestStoreCancellation opens the store cancellation and closes the flow, once", .timeLimit(.minutes(1)))
    func requestStoreCancellationOpensStoreOnce() {
        var storeCancellationCalls: [Bool] = []
        let model = makeModel { storeCancellationCalls.append($0) }

        model.requestStoreCancellation()
        model.requestStoreCancellation()

        #expect(storeCancellationCalls == [true])
        #expect(instrumentation.flowLoadFailures.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page load failure fires the error pixel and opens the store cancellation without closing the flow", .timeLimit(.minutes(1)))
    func loadFailureOpensStoreWithoutClosing() {
        var storeCancellationCalls: [Bool] = []
        let model = makeModel { storeCancellationCalls.append($0) }

        navigationErrors.send(TestError())

        #expect(storeCancellationCalls == [false])
        #expect(instrumentation.flowLoadFailures.count == 1)
        withExtendedLifetime(model) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cleared navigation error does nothing", .timeLimit(.minutes(1)))
    func clearedNavigationErrorIsIgnored() {
        var storeCancellationCalls: [Bool] = []
        let model = makeModel { storeCancellationCalls.append($0) }

        navigationErrors.send(nil)

        #expect(storeCancellationCalls.isEmpty)
        #expect(instrumentation.flowLoadFailures.isEmpty)
        withExtendedLifetime(model) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("Repeated load failures open the store cancellation only once", .timeLimit(.minutes(1)))
    func repeatedLoadFailuresOpenStoreOnce() {
        var storeCancellationCalls: [Bool] = []
        let model = makeModel { storeCancellationCalls.append($0) }

        navigationErrors.send(TestError())
        navigationErrors.send(TestError())

        #expect(storeCancellationCalls == [false])
        #expect(instrumentation.flowLoadFailures.count == 1)
        withExtendedLifetime(model) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test("A load failure after cancellation was requested is not reported", .timeLimit(.minutes(1)))
    func loadFailureAfterRequestIsIgnored() {
        var storeCancellationCalls: [Bool] = []
        let model = makeModel { storeCancellationCalls.append($0) }

        model.requestStoreCancellation()
        navigationErrors.send(TestError())

        #expect(storeCancellationCalls == [true])
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
    @Test("A cancellation detected after the App Store screen fires the cancelled pixel", .timeLimit(.minutes(1)))
    func appStoreSubscriptionCancelledFiresPixel() {
        let pixelKit = PixelKitMock()

        SubscriptionCancellationInstrumentation(pixelFiring: pixelKit).appStoreSubscriptionCancelled()

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationAppStoreCancelled, frequency: .standard)])
        #expect(SubscriptionPixel.subscriptionCancellationAppStoreCancelled.parameters == nil)
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
    @Test("A feature info failure fires the feature info failure pixel daily and count with the entitlement", .timeLimit(.minutes(1)), arguments: [
        (SubscriptionEntitlement.unknown, "unknown"),
        (.networkProtection, "Network Protection"),
        (.identityTheftRestorationGlobal, "Global Identity Theft Restoration")
    ])
    func featureInfoFailedFiresPixel(entitlement: SubscriptionEntitlement, expectedValue: String) {
        let pixelKit = PixelKitMock()

        SubscriptionCancellationInstrumentation(pixelFiring: pixelKit).featureInfoFailed(entitlement: entitlement)

        #expect(pixelKit.actualFireCalls == [ExpectedFireCall(pixel: SubscriptionPixel.subscriptionCancellationFeatureInfoFailure(entitlement: entitlement), frequency: .dailyAndCount)])
        #expect(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure(entitlement: entitlement).parameters == ["entitlement": expectedValue])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Pixel names match their definitions", .timeLimit(.minutes(1)))
    func pixelNames() {
        #expect(SubscriptionPixel.subscriptionCancellationCancelClick.name == "subscription_cancellation_cancel_click")
        #expect(SubscriptionPixel.subscriptionCancellationAppStoreCancelled.name == "subscription_cancellation_app_store_cancelled")
        #expect(SubscriptionPixel.subscriptionCancellationFlowLoadFailure(TestError()).name == "subscription_cancellation_flow_load_failure")
        #expect(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure(entitlement: .unknown).name == "subscription_cancellation_feature-info_failure")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancellation pixels use the standard platform suffix their definitions declare", .timeLimit(.minutes(1)))
    func cancellationPixelsUseStandardPlatformSuffix() {
        #expect(SubscriptionPixel.subscriptionCancellationCancelClick.platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionCancellationAppStoreCancelled.platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionCancellationFlowLoadFailure(TestError()).platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionCancellationFeatureInfoFailure(entitlement: .unknown).platformSuffixPolicy == .standard)
        #expect(SubscriptionPixel.subscriptionActive.platformSuffixPolicy == .legacyOmitted)
    }
}
