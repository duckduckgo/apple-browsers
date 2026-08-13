//
//  IPadOmnibarModelPickerControllerTests.swift
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
import XCTest
@testable import DuckDuckGo

@MainActor
final class IPadOmnibarModelPickerControllerTests: XCTestCase {

    private var sut: IPadOmnibarModelPickerController!
    private var preferences: StubPreferences!
    private var modelsService: StubModelsService!
    private var subscriptionManager: SubscriptionManagerMock!
    private var upsellPresenter: MockUpsellPresenter!

    override func setUp() {
        super.setUp()
        preferences = StubPreferences()
        modelsService = StubModelsService()
        subscriptionManager = SubscriptionManagerMock()
        upsellPresenter = MockUpsellPresenter()
        sut = IPadOmnibarModelPickerController(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager,
            upsellPresenter: upsellPresenter,
            updatedModelPickerFeature: MockUpdatedModelPickerFeature(isAvailable: false)
        )
    }

    override func tearDown() {
        sut = nil
        preferences = nil
        modelsService = nil
        subscriptionManager = nil
        upsellPresenter = nil
        super.tearDown()
    }

    func testWhenNoModelsLoadedThenMakeMenuReturnsNil() {
        XCTAssertNil(sut.makeMenu { _ in })
        XCTAssertFalse(sut.hasModels)
    }

    func testWhenSelectAccessibleModelThenSelectionPersistedToPreferences() {
        sut.modelStore.models = [makeModel(id: "gpt-5", shortName: "GPT-5")]

        sut.handleModelSelection("gpt-5")

        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
        XCTAssertTrue(upsellPresenter.presentedPurchaseFlows.isEmpty)
        XCTAssertTrue(upsellPresenter.presentedUpgradeFlows.isEmpty)
    }

    func testWhenNoModelsLoadedThenCurrentModelLabelFallsBackToCachedPreference() {
        preferences.selectedModelShortName = "Cached"

        XCTAssertEqual(sut.currentModelLabel, "Cached")
    }

    func testWhenModelsLoadedWithoutSelectionThenCurrentModelLabelIsFirstAccessibleModel() async {
        let updated = expectation(description: "models updated")
        modelsService.result = .success(AIChatModelsResponse(models: [makeRemoteModel(id: "gpt-5", shortName: "GPT-5")]))
        sut.onModelsUpdated = { updated.fulfill() }
        sut.activate()
        await fulfillment(of: [updated], timeout: 1)

        // No explicit selection — the chip should still resolve to the default (first accessible) model.
        XCTAssertEqual(sut.currentModelLabel, "GPT-5")
    }

    func testWhenModelsFetchedThenOnModelsUpdatedIsCalledAndMenuAvailable() async {
        let updated = expectation(description: "models updated")
        modelsService.result = .success(AIChatModelsResponse(models: [makeRemoteModel(id: "gpt-5", shortName: "GPT-5")]))
        sut.onModelsUpdated = { updated.fulfill() }

        sut.activate()

        await fulfillment(of: [updated], timeout: 1)
        XCTAssertTrue(sut.hasModels)
        XCTAssertNotNil(sut.makeMenu { _ in })
    }

    func testWhenUpdatedModelPickerIsDisabledThenMakeMenuBuildsLegacyMenu() throws {
        sut.modelStore.models = [
            makeModel(id: "free", shortName: "Free", accessTier: ["free"]),
            makeModel(id: "plus", shortName: "Plus", entityHasAccess: false, accessTier: ["plus"])
        ]

        let menu = try XCTUnwrap(sut.makeMenu { _ in })
        let sections = menu.children.compactMap { $0 as? UIMenu }

        XCTAssertEqual(sections.map(\.title), ["", UserText.aiChatPlusModelsSectionHeader])
        XCTAssertTrue(menu.children.allSatisfy { $0 is UIMenu })
    }

    func testWhenUpdatedModelPickerIsEnabledForFreeUserThenMakeMenuBuildsUpdatedMenu() throws {
        sut = makeSUTWithUpdatedModelPickerEnabled(userTier: .free)
        sut.modelStore.models = [
            makeModel(id: "free", shortName: "Free", accessTier: ["free"]),
            makeModel(id: "plus", shortName: "Plus", entityHasAccess: false, accessTier: ["plus"])
        ]

        let menu = try XCTUnwrap(sut.makeMenu { _ in })
        let availableActions = menu.children.compactMap { $0 as? UIAction }
        let gatedSection = menu.children.compactMap { $0 as? UIMenu }.first

        XCTAssertEqual(availableActions.map(\.title), ["free"])
        XCTAssertEqual(gatedSection?.title, UserText.aiChatModelPickerTryFree)
    }

    func testWhenUpdatedModelPickerIsEnabledForPlusUserThenGatedSectionUsesProTitle() throws {
        sut = makeSUTWithUpdatedModelPickerEnabled(userTier: .plus)
        sut.modelStore.models = [
            makeModel(id: "pro", shortName: "Pro", entityHasAccess: false, accessTier: ["pro"])
        ]

        let menu = try XCTUnwrap(sut.makeMenu { _ in })
        let gatedSection = menu.children.compactMap { $0 as? UIMenu }.first

        XCTAssertEqual(gatedSection?.title, UserText.aiChatModelPickerAvailableWithPro)
    }

    func testWhenModelActionPerformedThenBothMenuVariantsForwardSameModelId() throws {
        for isUpdatedModelPickerEnabled in [false, true] {
            sut = makeSUT(updatedModelPickerEnabled: isUpdatedModelPickerEnabled)
            sut.modelStore.models = [makeModel(id: "gpt-5", shortName: "GPT-5")]
            var selectedModelId: String?

            let menu = try XCTUnwrap(sut.makeMenu { selectedModelId = $0 })
            let action = try XCTUnwrap(actions(in: menu).first)
            action.performWithSender(nil, target: nil)

            XCTAssertEqual(selectedModelId, "gpt-5")
        }
    }

    func testWhenModelSelectedAfterFetchThenShortNamePersistedAndDisplayed() async {
        let updated = expectation(description: "models updated")
        modelsService.result = .success(AIChatModelsResponse(models: [makeRemoteModel(id: "gpt-5", shortName: "GPT-5")]))
        sut.onModelsUpdated = { updated.fulfill() }
        sut.activate()
        await fulfillment(of: [updated], timeout: 1)

        sut.handleModelSelection("gpt-5")

        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
        XCTAssertEqual(preferences.selectedModelShortName, "GPT-5")
        XCTAssertEqual(sut.currentModelLabel, "GPT-5")
    }

    func testWhenModelSelectedThenCurrentModelIdReflectsSelection() async {
        let updated = expectation(description: "models updated")
        modelsService.result = .success(AIChatModelsResponse(models: [
            makeRemoteModel(id: "gpt-5", shortName: "GPT-5"),
            makeRemoteModel(id: "mistral", shortName: "Mistral")
        ]))
        sut.onModelsUpdated = { updated.fulfill() }
        sut.activate()
        await fulfillment(of: [updated], timeout: 1)

        sut.handleModelSelection("mistral")

        XCTAssertEqual(sut.currentModelId, "mistral")
    }

    func testWhenNoSelectionThenCurrentModelIdFallsBackToFirstAccessibleModel() async {
        let updated = expectation(description: "models updated")
        modelsService.result = .success(AIChatModelsResponse(models: [makeRemoteModel(id: "gpt-5", shortName: "GPT-5")]))
        sut.onModelsUpdated = { updated.fulfill() }
        sut.activate()
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertEqual(sut.currentModelId, "gpt-5")
    }

    // MARK: - Selection (gated → upsell)

    func testWhenFreeUserSelectsGatedPlusModelThenRoutesPurchaseWithoutChangingSelection() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .free, hasActiveSubscription: false)
        sut.modelStore.models = [
            makeModel(id: "gpt-5", shortName: "GPT-5"),
            makeModel(id: "claude", shortName: "Claude", entityHasAccess: false, accessTier: ["plus", "pro", "internal"])
        ]
        sut.handleModelSelection("gpt-5")

        sut.handleModelSelection("claude")

        XCTAssertEqual(upsellPresenter.presentedPurchaseFlows.count, 1)
        XCTAssertEqual(upsellPresenter.presentedPurchaseFlows.first?.source, .modelPicker)
        XCTAssertTrue(upsellPresenter.presentedUpgradeFlows.isEmpty)
        XCTAssertEqual(preferences.selectedModelId, "gpt-5", "A gated selection must not change the persisted model")
    }

    func testWhenPlusUserSelectsGatedProModelThenRoutesUpgradeWithoutChangingSelection() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeModel(id: "gpt-5", shortName: "GPT-5"),
            makeModel(id: "claude", shortName: "Claude", entityHasAccess: false, accessTier: ["pro", "internal"])
        ]
        sut.handleModelSelection("gpt-5")

        sut.handleModelSelection("claude")

        XCTAssertEqual(upsellPresenter.presentedUpgradeFlows.count, 1)
        XCTAssertEqual(upsellPresenter.presentedUpgradeFlows.first?.source, .modelPicker)
        XCTAssertTrue(upsellPresenter.presentedPurchaseFlows.isEmpty)
        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
    }

    func testWhenUserHasAccessToGatedTierModelThenSelectsWithoutUpsell() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .pro, hasActiveSubscription: true)
        // entityHasAccess reflects the user's tier — a pro user has access to a pro-tier model.
        sut.modelStore.models = [makeModel(id: "claude", shortName: "Claude", entityHasAccess: true, accessTier: ["pro", "internal"])]

        sut.handleModelSelection("claude")

        XCTAssertEqual(preferences.selectedModelId, "claude")
        XCTAssertTrue(upsellPresenter.presentedPurchaseFlows.isEmpty)
        XCTAssertTrue(upsellPresenter.presentedUpgradeFlows.isEmpty)
    }

    // MARK: - Pending gated selection re-apply

    func testWhenGatedModelBecomesAccessibleAfterRefreshThenPendingModelIsApplied() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .free, hasActiveSubscription: false)
        sut.modelStore.models = [
            makeModel(id: "gpt-5", shortName: "GPT-5"),
            makeModel(id: "claude", shortName: "Claude", entityHasAccess: false, accessTier: ["plus", "pro", "internal"])
        ]
        sut.handleModelSelection("gpt-5")
        sut.handleModelSelection("claude")
        XCTAssertEqual(preferences.selectedModelId, "gpt-5")

        // Subscription purchased: /models re-fetched with the gated model now accessible.
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeModel(id: "gpt-5", shortName: "GPT-5"),
            makeModel(id: "claude", shortName: "Claude", entityHasAccess: true, accessTier: ["plus", "pro", "internal"])
        ]
        sut.handleModelsUpdated()

        XCTAssertEqual(preferences.selectedModelId, "claude")
    }

    func testWhenGatedModelStaysInaccessibleAfterRefreshThenPendingModelNotApplied() {
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .free, hasActiveSubscription: false)
        sut.modelStore.models = [
            makeModel(id: "gpt-5", shortName: "GPT-5"),
            makeModel(id: "claude", shortName: "Claude", entityHasAccess: false, accessTier: ["plus", "pro", "internal"])
        ]
        sut.handleModelSelection("gpt-5")
        sut.handleModelSelection("claude")

        // A refresh that does not grant access (e.g. user dismissed the purchase flow).
        sut.handleModelsUpdated()

        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
    }

    // MARK: - Helpers

    private func makeSUTWithUpdatedModelPickerEnabled(userTier: AIChatUserTier) -> IPadOmnibarModelPickerController {
        let sut = makeSUT(updatedModelPickerEnabled: true)
        sut.modelStore.subscriptionState = SubscriptionState(userTier: userTier, hasActiveSubscription: userTier != .free)
        return sut
    }

    private func makeSUT(updatedModelPickerEnabled: Bool) -> IPadOmnibarModelPickerController {
        IPadOmnibarModelPickerController(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager,
            upsellPresenter: upsellPresenter,
            updatedModelPickerFeature: MockUpdatedModelPickerFeature(isAvailable: updatedModelPickerEnabled)
        )
    }

    private func actions(in menu: UIMenu) -> [UIAction] {
        menu.children.flatMap { element -> [UIAction] in
            if let action = element as? UIAction {
                return [action]
            }
            return (element as? UIMenu)?.children.compactMap { $0 as? UIAction } ?? []
        }
    }

    private func makeModel(
        id: String,
        shortName: String,
        entityHasAccess: Bool = true,
        accessTier: [String] = []
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: shortName,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: entityHasAccess,
            accessTier: accessTier
        )
    }

    private func makeRemoteModel(id: String, shortName: String) -> AIChatRemoteModel {
        AIChatRemoteModel(
            id: id,
            name: id,
            modelShortName: shortName,
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: false,
            supportedTools: [],
            accessTier: []
        )
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

private struct MockUpdatedModelPickerFeature: UpdatedModelPickerFeatureProviding {
    let isAvailable: Bool
}

private final class StubPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

@MainActor
private final class StubModelsService: AIChatModelsProviding {
    var result: Result<AIChatModelsResponse, Error> = .success(AIChatModelsResponse(models: []))

    func fetchModels() async throws -> AIChatModelsResponse { try result.get() }
}
