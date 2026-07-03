//
//  IPadOmnibarReasoningPickerControllerTests.swift
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

import AIChat
import Combine
import SubscriptionTestingUtilities
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class IPadOmnibarReasoningPickerControllerTests: XCTestCase {

    private var sut: IPadOmnibarReasoningPickerController!
    private var store: UTIModelStore!
    private var preferences: StubReasoningPreferences!
    private var upsellPresenter: MockUpsellPresenter!

    override func setUp() {
        super.setUp()
        preferences = StubReasoningPreferences()
        store = UTIModelStore(
            modelsService: StubModelsService(),
            preferences: preferences,
            subscriptionManager: SubscriptionManagerMock()
        )
        upsellPresenter = MockUpsellPresenter()
        sut = IPadOmnibarReasoningPickerController(
            store: store,
            upsellPresenter: upsellPresenter
        )
    }

    override func tearDown() {
        sut = nil
        store = nil
        preferences = nil
        upsellPresenter = nil
        super.tearDown()
    }

    // MARK: - Availability

    func testWhenModelSupportsReasoningPickerThenIsAvailable() {
        store.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        XCTAssertTrue(sut.isReasoningPickerAvailable)
    }

    func testWhenModelHasSingleReasoningModeThenNotAvailable() {
        store.models = [makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low])]

        XCTAssertFalse(sut.isReasoningPickerAvailable)
    }

    func testWhenNoModelsThenMenuIsNil() {
        XCTAssertNil(sut.makeMenu())
        XCTAssertFalse(sut.isReasoningPickerAvailable)
    }

    func testWhenModelSupportsReasoningPickerThenMenuIsNotNil() {
        store.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        XCTAssertNotNil(sut.makeMenu())
    }

    // MARK: - Selection (accessible)

    func testWhenAccessibleModeSelectedThenPersistedWithoutUpsell() {
        store.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        sut.handleReasoningModeSelection(.reasoning)

        XCTAssertEqual(preferences.selectedReasoningMode, .reasoning)
        XCTAssertTrue(upsellPresenter.presentedPurchaseFlows.isEmpty)
        XCTAssertTrue(upsellPresenter.presentedUpgradeFlows.isEmpty)
    }

    func testCurrentReasoningModeReflectsSelection() {
        store.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]

        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(sut.currentReasoningMode, .extendedReasoning)
    }

    // MARK: - Selection (gated → upsell)

    func testWhenFreeUserSelectsGatedExtendedThenRoutesPurchaseWithoutChangingSelection() {
        store.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]
        sut.handleReasoningModeSelection(.reasoning)

        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(upsellPresenter.presentedPurchaseFlows.count, 1)
        XCTAssertEqual(upsellPresenter.presentedPurchaseFlows.first?.source, .reasoningPicker)
        XCTAssertEqual(preferences.selectedReasoningMode, .reasoning, "Gated selection must not change the persisted mode")
    }

    func testWhenPlusUserSelectsGatedExtendedThenRoutesUpgradeWithoutChangingSelection() {
        store.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        store.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]
        sut.handleReasoningModeSelection(.reasoning)

        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(upsellPresenter.presentedUpgradeFlows.count, 1)
        XCTAssertEqual(upsellPresenter.presentedUpgradeFlows.first?.source, .reasoningPicker)
        XCTAssertEqual(preferences.selectedReasoningMode, .reasoning)
    }

    func testWhenProUserSelectsGatedExtendedThenSelects() {
        store.subscriptionState = SubscriptionState(userTier: .pro, hasActiveSubscription: true)
        store.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]

        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(preferences.selectedReasoningMode, .extendedReasoning)
        XCTAssertTrue(upsellPresenter.presentedPurchaseFlows.isEmpty)
        XCTAssertTrue(upsellPresenter.presentedUpgradeFlows.isEmpty)
    }

    // MARK: - Pending gated selection re-apply

    func testWhenGatedSelectionBecomesAccessibleAfterRefreshThenPendingModeIsApplied() {
        store.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        store.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumGatedForPlus()
            )
        ]
        sut.handleReasoningModeSelection(.reasoning)
        sut.handleReasoningModeSelection(.extendedReasoning)
        XCTAssertEqual(preferences.selectedReasoningMode, .reasoning)

        // Subscription upgraded: /models re-fetched with the effort now accessible.
        store.subscriptionState = SubscriptionState(userTier: .pro, hasActiveSubscription: true)
        store.models = [
            makeReasoningModel(
                id: "gpt-5.2",
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: gpt52MediumAccessibleForPro()
            )
        ]
        sut.handleModelsUpdated()

        XCTAssertEqual(preferences.selectedReasoningMode, .extendedReasoning)
    }

    // MARK: - Resolved effort for submit

    func testSelectedReasoningEffortResolvesFromSelectedMode() {
        store.subscriptionState = SubscriptionState(userTier: .pro, hasActiveSubscription: true)
        store.models = [makeReasoningModel(id: "gpt-5.2", supportedReasoningEffort: [.none, .low, .medium])]
        sut.handleReasoningModeSelection(.extendedReasoning)

        XCTAssertEqual(sut.selectedReasoningEffort, .medium)
    }

    func testSelectedReasoningEffortIsNilWhenPickerUnavailable() {
        store.models = [makeReasoningModel(id: "gpt-oss", supportedReasoningEffort: [.low])]

        XCTAssertNil(sut.selectedReasoningEffort)
    }

    // MARK: - Helpers

    private func makeReasoningModel(
        id: String,
        supportedReasoningEffort: [AIChatReasoningEffort],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess
        )
    }

    private func gpt52MediumGatedForPlus() -> [AIChatReasoningEffortAccess] {
        [
            AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
        ]
    }

    private func gpt52MediumAccessibleForPro() -> [AIChatReasoningEffortAccess] {
        [
            AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
            AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: true)
        ]
    }
}

private final class MockUpsellPresenter: DuckAISubscriptionUpselling {
    var presentedPurchaseFlows: [(source: SubscriptionFlowSource, isAITabState: Bool)] = []
    var presentedUpgradeFlows: [(source: SubscriptionFlowSource, isAITabState: Bool)] = []

    func presentPurchaseFlow(source: SubscriptionFlowSource, isAITabState: Bool) {
        presentedPurchaseFlows.append((source, isAITabState))
    }

    func presentUpgradeFlow(source: SubscriptionFlowSource, isAITabState: Bool) {
        presentedUpgradeFlows.append((source, isAITabState))
    }
}

private final class StubReasoningPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class StubModelsService: AIChatModelsProviding {
    var result: Result<AIChatModelsResponse, Error> = .success(AIChatModelsResponse(models: []))

    func fetchModels() async throws -> AIChatModelsResponse { try result.get() }
}
