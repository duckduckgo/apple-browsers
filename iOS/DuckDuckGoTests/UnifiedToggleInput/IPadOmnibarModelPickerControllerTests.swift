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

    override func setUp() {
        super.setUp()
        preferences = StubPreferences()
        modelsService = StubModelsService()
        subscriptionManager = SubscriptionManagerMock()
        sut = IPadOmnibarModelPickerController(
            modelsService: modelsService,
            preferences: preferences,
            subscriptionManager: subscriptionManager
        )
    }

    override func tearDown() {
        sut = nil
        preferences = nil
        modelsService = nil
        subscriptionManager = nil
        super.tearDown()
    }

    func testWhenNoModelsLoadedThenMakeMenuReturnsNil() {
        XCTAssertNil(sut.makeMenu { _ in })
        XCTAssertFalse(sut.hasModels)
    }

    func testWhenSelectModelThenSelectionPersistedToPreferences() {
        sut.selectModel("gpt-5")

        XCTAssertEqual(preferences.selectedModelId, "gpt-5")
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

    func testWhenModelSelectedAfterFetchThenShortNamePersistedAndDisplayed() async {
        let updated = expectation(description: "models updated")
        modelsService.result = .success(AIChatModelsResponse(models: [makeRemoteModel(id: "gpt-5", shortName: "GPT-5")]))
        sut.onModelsUpdated = { updated.fulfill() }
        sut.activate()
        await fulfillment(of: [updated], timeout: 1)

        sut.selectModel("gpt-5")

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

        sut.selectModel("mistral")

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

    // MARK: - Helpers

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

private final class StubPreferences: AIChatPreferencesPersisting {
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
