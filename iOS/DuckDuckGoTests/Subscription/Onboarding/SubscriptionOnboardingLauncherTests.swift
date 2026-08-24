//
//  SubscriptionOnboardingLauncherTests.swift
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

import XCTest
import SwiftUI
import Persistence
import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingLauncherTests: XCTestCase {

    private var subscriptionManager: SubscriptionManagerMock!

    override func setUp() {
        super.setUp()
        subscriptionManager = SubscriptionManagerMock()
    }

    override func tearDown() {
        subscriptionManager = nil
        super.tearDown()
    }

    // MARK: - postCheckout

    /// A full-happy-path regression check, not a discriminating one — it would pass even without the
    /// entitlement fetch wired up, since `.allEnabled` is the checklist's own default. The next test is what
    /// actually proves the fetched entitlement is threaded through.
    func testWhenBuildingPostCheckoutWithFullEntitlementThenTheFullSequenceIsBuilt() async throws {
        subscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection,
                                              .identityTheftRestoration, .identityTheftRestorationGlobal,
                                              .paidAIChat]

        let result = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertEqual(flow.sequence,
                       [.orderConfirmation, .welcome, .vpnActivation, .vpnWidget, .vpnTips, .idtr, .duckAI, .progress])
    }

    /// The fetched entitlement, not a caller-supplied default, is what gates the built flow's sequence.
    func testWhenBuildingPostCheckoutThenTheFetchedEntitlementGatesTheSequence() async throws {
        subscriptionManager.resultFeatures = [.dataBrokerProtection, .identityTheftRestoration]

        let result = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertEqual(flow.sequence, [.orderConfirmation, .welcome, .idtr, .progress])
    }

    /// The whole point of the empty-checklist guard: nothing entitled and PIR unavailable means nothing to
    /// show, so the launcher refuses to build a flow at all rather than presenting a broken, empty run.
    func testWhenTheChecklistIsEmptyThenPostCheckoutReturnsNil() async {
        subscriptionManager.resultFeatures = []

        let flow = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: false,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            pirScreen: { EmptyView() })

        XCTAssertNil(flow)
    }

    // MARK: - subscriptionSettings

    func testWhenBuildingSubscriptionSettingsThenItResumesAtTheFirstUnfinishedGatedSection() async throws {
        subscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection,
                                              .identityTheftRestoration, .paidAIChat]
        var persistor = makePersistor()
        persistor.markComplete(.vpn)

        let result = await SubscriptionOnboardingFlowViewModel.subscriptionSettings(
            persistor: persistor,
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertEqual(flow.sequence, [.vpnWidget, .vpnTips, .idtr, .duckAI, .progress])
    }

    func testWhenTheChecklistIsEmptyThenSubscriptionSettingsReturnsNil() async {
        subscriptionManager.resultFeatures = []

        let flow = await SubscriptionOnboardingFlowViewModel.subscriptionSettings(
            persistor: makePersistor(),
            isPIRAvailable: false,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            pirScreen: { EmptyView() })

        XCTAssertNil(flow)
    }

    // MARK: - Helpers

    private func makePersistor() -> SubscriptionOnboardingProgressPersistor {
        SubscriptionOnboardingProgressPersistor(keyValueStore: InMemoryThrowingStore())
    }
}

/// A local stub rather than `PersistenceTestingUtils`
private final class InMemoryThrowingStore: ThrowingKeyValueStoring {

    private var values: [String: Any] = [:]

    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}
