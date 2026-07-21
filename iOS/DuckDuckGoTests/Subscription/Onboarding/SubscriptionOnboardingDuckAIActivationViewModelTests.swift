//
//  SubscriptionOnboardingDuckAIActivationViewModelTests.swift
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
import AIChat
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingDuckAIActivationViewModelTests: XCTestCase {

    func testOnAppearFetchesAndPopulatesModels() {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])])
        let viewModel = makeViewModel(provider: provider)

        viewModel.onAppear()

        XCTAssertEqual(viewModel.models.count, 2)
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testOnAppearCalledTwiceFetchesOnce() {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])])
        let viewModel = makeViewModel(provider: provider)

        viewModel.onAppear()
        viewModel.onAppear()

        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testAvailableModelsDropsInaccessibleAndOrdersPremiumFirst() {
        let provider = MockAIModelProvider(models: [
            model("free1", tier: ["free"]),
            model("plus1", tier: ["plus"]),
            model("noAccess", tier: ["pro"], hasAccess: false),
            model("free2", tier: ["free"])
        ])
        let viewModel = makeViewModel(provider: provider)

        viewModel.onAppear()

        XCTAssertEqual(viewModel.availableModels.map(\.id), ["plus1", "free1", "free2"])
    }

    func testOnAppearSelectsPersistedModel() {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])], persistedModelID: "b")
        let viewModel = makeViewModel(provider: provider)

        viewModel.onAppear()

        XCTAssertEqual(viewModel.selectedModelID, "b")
    }

    func testOnAppearWithNoModelsLeavesSelectionNil() {
        let provider = MockAIModelProvider(models: [])
        let viewModel = makeViewModel(provider: provider)

        viewModel.onAppear()

        XCTAssertTrue(viewModel.availableModels.isEmpty)
        XCTAssertNil(viewModel.selectedModelID)
    }

    func testSelectionPreservedAcrossModelsRefresh() {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])], persistedModelID: "a")
        let viewModel = makeViewModel(provider: provider)
        viewModel.onAppear()
        viewModel.select("b")

        provider.onModelsUpdated?()

        XCTAssertEqual(viewModel.selectedModelID, "b")
    }

    func testSelectUpdatesSelectionWithoutPersisting() {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])])
        let viewModel = makeViewModel(provider: provider)
        viewModel.onAppear()

        viewModel.select("b")

        XCTAssertEqual(viewModel.selectedModelID, "b")
        XCTAssertNil(provider.updatedModelID)
    }

    func testStartChatPersistsSelectedModel() {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])], persistedModelID: "a")
        let viewModel = makeViewModel(provider: provider)
        viewModel.onAppear()

        viewModel.startChat()

        XCTAssertEqual(provider.updatedModelID, "a")
    }

    func testStartChatReportsSectionComplete() {
        let delegate = SpySectionDelegate()
        let viewModel = makeViewModel(provider: MockAIModelProvider(models: []), delegate: delegate)

        viewModel.startChat()

        XCTAssertEqual(delegate.completedSections, [.duckAI])
    }

    // MARK: - Helpers

    private func makeViewModel(provider: MockAIModelProvider,
                               delegate: SubscriptionOnboardingSectionDelegate? = nil) -> SubscriptionOnboardingDuckAIActivationViewModel {
        SubscriptionOnboardingDuckAIActivationViewModel(modelProvider: provider, delegate: delegate)
    }

    private func model(_ id: String, name: String = "Model", tier: [String], hasAccess: Bool = true) -> AIChatModel {
        AIChatModel(id: id, name: name, provider: .openAI, supportsImageUpload: false, entityHasAccess: hasAccess, accessTier: tier)
    }
}

// MARK: - Test doubles

@MainActor
private final class MockAIModelProvider: SubscriptionOnboardingAIModelProviding {
    let models: [AIChatModel]
    var persistedModelID: String?
    var onModelsUpdated: (() -> Void)?
    private(set) var fetchCallCount = 0
    private(set) var updatedModelID: String?

    init(models: [AIChatModel], persistedModelID: String? = nil) {
        self.models = models
        self.persistedModelID = persistedModelID
    }

    func fetchModels() {
        fetchCallCount += 1
        onModelsUpdated?()
    }

    func updateSelectedModel(_ modelID: String) {
        updatedModelID = modelID
    }
}

private final class SpySectionDelegate: SubscriptionOnboardingSectionDelegate {
    private(set) var completedSections: [SubscriptionOnboardingSection] = []
    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        completedSections.append(section)
    }
}
