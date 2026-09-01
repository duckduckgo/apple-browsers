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
import Combine
import SwiftUI
import Persistence
import Subscription
import SubscriptionTestingUtilities
import DataBrokerProtection_iOS
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingLauncherTests: XCTestCase {

    private var subscriptionManager: SubscriptionManagerMock!
    private var vpnController: MockVPNController!
    private var profileStateManager: MockDBPProfileStateManager!
    private var freemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!

    override func setUp() {
        super.setUp()
        subscriptionManager = SubscriptionManagerMock()
        vpnController = MockVPNController(isConfigured: false)
        profileStateManager = MockDBPProfileStateManager(profileState: .noProfile)
        freemiumDBPUserStateManager = MockFreemiumDBPUserStateManager(didActivate: false)
    }

    override func tearDown() {
        subscriptionManager = nil
        vpnController = nil
        profileStateManager = nil
        freemiumDBPUserStateManager = nil
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
            vpnController: vpnController,
            profileStateManager: profileStateManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertEqual(flow.sequence,
                       [.orderConfirmation, .welcome, .vpnActivation, .vpnWidget, .vpnTips, .idtr, .duckAI, .progress])
    }

    /// An installed VPN config skips only the activation section — widget/tips are a different signal.
    func testWhenAVPNConfigurationIsAlreadyInstalledThenOnlyVPNActivationIsSkipped() async throws {
        subscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection,
                                              .identityTheftRestoration, .identityTheftRestorationGlobal,
                                              .paidAIChat]

        let result = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            vpnController: MockVPNController(isConfigured: true),
            profileStateManager: profileStateManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertEqual(flow.sequence, [.orderConfirmation, .welcome, .vpnWidget, .vpnTips, .idtr, .duckAI, .progress])
    }

    /// An existing PIR profile marks `.pir` complete — mirrors the VPN backfill above. `.pir` isn't a
    /// section, so this checks `completedItems`/completion percentage rather than `sequence`.
    func testWhenAPIRProfileAlreadyExistsThenPIRIsMarkedComplete() async throws {
        subscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection,
                                              .identityTheftRestoration, .identityTheftRestorationGlobal,
                                              .paidAIChat]

        let result = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            vpnController: vpnController,
            profileStateManager: MockDBPProfileStateManager(profileState: .hasProfile),
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertTrue(flow.progress.completedItems.contains(.pir))
    }

    /// A freemium activation with no saved profile yet also counts — matches `SettingsViewModel.isPIRActivated`.
    func testWhenFreemiumDidActivateButNoProfileExistsThenPIRIsStillMarkedComplete() async throws {
        subscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection,
                                              .identityTheftRestoration, .identityTheftRestorationGlobal,
                                              .paidAIChat]

        let result = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            vpnController: vpnController,
            profileStateManager: profileStateManager,
            freemiumDBPUserStateManager: MockFreemiumDBPUserStateManager(didActivate: true),
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertTrue(flow.progress.completedItems.contains(.pir))
    }

    /// No existing profile and no freemium activation: `.pir` stays unmarked, same as before this backfill.
    func testWhenNoPIRProfileOrFreemiumActivationExistsThenPIRIsNotMarkedComplete() async throws {
        subscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection,
                                              .identityTheftRestoration, .identityTheftRestorationGlobal,
                                              .paidAIChat]

        let result = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            vpnController: vpnController,
            profileStateManager: profileStateManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            pirScreen: { EmptyView() })
        let flow = try XCTUnwrap(result)

        XCTAssertFalse(flow.progress.completedItems.contains(.pir))
    }

    /// The fetched entitlement, not a caller-supplied default, is what gates the built flow's sequence.
    func testWhenBuildingPostCheckoutThenTheFetchedEntitlementGatesTheSequence() async throws {
        subscriptionManager.resultFeatures = [.dataBrokerProtection, .identityTheftRestoration]

        let result = await SubscriptionOnboardingFlowViewModel.postCheckout(
            persistor: makePersistor(),
            isPIRAvailable: true,
            subscriptionManager: subscriptionManager,
            onFinish: {},
            vpnController: vpnController,
            profileStateManager: profileStateManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
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
            vpnController: vpnController,
            profileStateManager: profileStateManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
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

/// Only `isVPNConfigured()` matters here; connection state and `start()` are unused.
private struct MockVPNController: SubscriptionOnboardingVPNControlling {
    let isConfigured: Bool

    var isConnected: Bool { false }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var configurationDeniedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var controllerErrorPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }

    func start() async {}
    func isVPNConfigured() async -> Bool { isConfigured }
}

private struct MockDBPProfileStateManager: DBPProfileStateManaging {
    let profileState: DBPProfileState

    func recordProfileSaved() {}
    func recordProfileDeleted() {}
    func reconcileProfileState(hasSavedProfile: Bool) {}
}

private struct MockFreemiumDBPUserStateManager: FreemiumDBPUserStateManaging {
    let didActivate: Bool

    var firstProfileSavedTimestamp: Date? { nil }
    var firstScanResult: FreemiumFirstScanResult? { nil }
    var upgradeToSubscriptionTimestamp: Date? { nil }

    func recordProfileSavedIfNeeded() async {}
    func recordFirstScanResultIfNeeded(hasMatches: Bool) async {}
    func recordSubscriptionUpgradeIfEligible() async {}
    func resetAllState() {}
}
