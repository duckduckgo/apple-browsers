//
//  SubscriptionOnboardingDuckAIViewModelTests.swift
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
import XCTest
import AIChat
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingDuckAIViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    func testWhenOnAppearThenFetchesAndPopulatesModels() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])])
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$models, until: { !$0.isEmpty }) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.models.count, 2)
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testWhenOnAppearIsCalledTwiceThenFetchesOnce() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])])
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$models, until: { !$0.isEmpty }) {
            viewModel.onAppear()
            viewModel.onAppear()
        }

        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testWhenModelsLoadThenAvailableModelsDropInaccessibleAndOrderPremiumFirst() async {
        let provider = MockAIModelProvider(models: [
            model("free1", tier: ["free"]),
            model("plus1", tier: ["plus"]),
            model("noAccess", tier: ["pro"], hasAccess: false),
            model("free2", tier: ["free"])
        ])
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$models, until: { !$0.isEmpty }) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.availableModels.map(\.id), ["plus1", "free1", "free2"])
    }

    func testWhenOnAppearThenSelectsMostPremiumAvailableModel() async {
        // "a" is advanced (non-free tier); "b" is a free-tier model. The default selection must be the most
        // premium available model, and must not be swayed by whatever was previously persisted.
        let provider = MockAIModelProvider(models: [model("b", tier: ["free"]), model("a", tier: ["plus"])], persistedModelID: "b")
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$selectedModelID, until: { $0 != nil }) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.selectedModelID, "a")
    }

    func testWhenOnAppearWithMultiplePremiumModelsThenSelectsFirstInList() async {
        // Two advanced models — the most premium default resolves to the first one in list order.
        let provider = MockAIModelProvider(models: [
            model("free1", tier: ["free"]),
            model("premium1", tier: ["plus"]),
            model("premium2", tier: ["pro"])
        ])
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$selectedModelID, until: { $0 != nil }) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.selectedModelID, "premium1")
    }

    func testWhenOnAppearWithNoPremiumModelsThenSelectsFirstAvailable() async {
        // No advanced models — the default falls back to the first accessible (free-tier) model in list order.
        let provider = MockAIModelProvider(models: [model("free1", tier: ["free"]), model("free2", tier: ["free"])])
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$selectedModelID, until: { $0 != nil }) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.selectedModelID, "free1")
    }

    func testWhenOnAppearWithNoModelsThenSelectionRemainsNil() async {
        let provider = MockAIModelProvider(models: [])
        let (viewModel, prefetcher) = makeViewModel(provider: provider)

        await wait(prefetcher.$models, until: { if case .failed = $0 { return true } else { return false } }) {
            viewModel.onAppear()
        }

        XCTAssertTrue(viewModel.availableModels.isEmpty)
        XCTAssertNil(viewModel.selectedModelID)
    }

    func testWhenModelsLoadThenUserSelectionSurvives() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])], persistedModelID: "a")
        let (viewModel, _) = makeViewModel(provider: provider)

        // Select before the async fetch resolves; the load must not overwrite the user's choice with the default one.
        await wait(viewModel.$models, until: { !$0.isEmpty }) {
            viewModel.onAppear()
            viewModel.select("b")
        }

        XCTAssertEqual(viewModel.selectedModelID, "b")
    }

    func testWhenSelectThenSelectionUpdatesWithoutPersisting() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])])
        let (viewModel, _) = makeViewModel(provider: provider)
        await wait(viewModel.$models, until: { !$0.isEmpty }) {
            viewModel.onAppear()
        }

        viewModel.select("b")

        XCTAssertEqual(viewModel.selectedModelID, "b")
        XCTAssertNil(provider.updatedModelID)
    }

    func testWhenStartChatThenSelectedModelIsPersisted() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])], persistedModelID: "a")
        let (viewModel, _) = makeViewModel(provider: provider)
        await wait(viewModel.$selectedModelID, until: { $0 != nil }) {
            viewModel.onAppear()
        }

        viewModel.startChat()

        XCTAssertEqual(provider.updatedModelID, "a")
    }

    func testWhenStartChatThenRequestsDuckAIChatWithoutCompletingSection() async {
        let delegate = SpySectionDelegate()
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])], persistedModelID: "a")
        let (viewModel, _) = makeViewModel(provider: provider, delegate: delegate)
        await wait(viewModel.$selectedModelID, until: { $0 != nil }) {
            viewModel.onAppear()
        }

        viewModel.startChat()

        XCTAssertEqual(delegate.requestedChatModelIDs, ["a"])
        // Completion is deferred until the chat is dismissed (sectionDidFinishDuckAIChat).
        XCTAssertTrue(delegate.completedSections.isEmpty)
    }

    // MARK: - Helpers

    private func makeViewModel(provider: MockAIModelProvider,
                               delegate: SubscriptionOnboardingSectionDelegate? = nil)
    -> (viewModel: SubscriptionOnboardingDuckAIViewModel, prefetcher: SubscriptionOnboardingPrefetcher) {
        let prefetcher = SubscriptionOnboardingPrefetcher(modelProvider: provider)
        let viewModel = SubscriptionOnboardingDuckAIViewModel(prefetcher: prefetcher, delegate: delegate)
        return (viewModel, prefetcher)
    }

    private func model(_ id: String, name: String = "Model", tier: [String], hasAccess: Bool = true) -> AIChatModel {
        AIChatModel(id: id, name: name, provider: .openAI, supportsImageUpload: false, entityHasAccess: hasAccess, accessTier: tier)
    }

    /// Runs `trigger`, then waits until `publisher` emits a value satisfying `predicate`. 
    private func wait<T>(_ publisher: Published<T>.Publisher,
                         until predicate: @escaping (T) -> Bool,
                         trigger: () -> Void) async {
        let expectation = expectation(description: "publisher satisfies predicate")
        var fulfilled = false
        publisher
            .sink { emitted in
                if predicate(emitted), !fulfilled {
                    fulfilled = true
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        trigger()
        await fulfillment(of: [expectation], timeout: 1)
    }
}

// MARK: - Test doubles

@MainActor
private final class MockAIModelProvider: SubscriptionOnboardingAIModelProviding {
    private let models: [AIChatModel]
    var persistedModelID: String?
    private(set) var fetchCallCount = 0
    private(set) var updatedModelID: String?

    init(models: [AIChatModel], persistedModelID: String? = nil) {
        self.models = models
        self.persistedModelID = persistedModelID
    }

    func fetchModels() async -> [AIChatModel] {
        fetchCallCount += 1
        return models
    }

    func updateSelectedModel(_ modelID: String) {
        updatedModelID = modelID
    }
}

private final class SpySectionDelegate: SubscriptionOnboardingSectionDelegate {
    private(set) var completedSections: [SubscriptionOnboardingSection] = []
    private(set) var requestedChatModelIDs: [String?] = []
    private(set) var requestedWebChatModelSettingIDs: [String?] = []
    private(set) var finishedChatCount = 0
    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        completedSections.append(section)
    }
    func sectionDidRequestDuckAIChat(modelID: String?) {
        requestedChatModelIDs.append(modelID)
    }
    func sectionDidRequestDuckAIWebChat(modelSettingID: String?) {
        requestedWebChatModelSettingIDs.append(modelSettingID)
    }
    func sectionDidFinishDuckAIChat() {
        finishedChatCount += 1
    }
    func sectionDidRequestAdvance() {}
    func sectionDidRequestGoBack() {}
}
