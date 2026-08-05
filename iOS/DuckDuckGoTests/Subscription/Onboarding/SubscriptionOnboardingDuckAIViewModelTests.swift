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
@testable import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

@MainActor
final class SubscriptionOnboardingDuckAIViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    func testWhenOnAppearThenFetchesAndPopulatesModels() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])])
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$availableModels, until: { !$0.isEmpty }) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.availableModels.count, 2)
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testWhenOnAppearIsCalledTwiceThenFetchesOnce() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])])
        let (viewModel, _) = makeViewModel(provider: provider)

        await wait(viewModel.$availableModels, until: { !$0.isEmpty }) {
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

        await wait(viewModel.$availableModels, until: { !$0.isEmpty }) {
            viewModel.onAppear()
        }

        XCTAssertEqual(viewModel.availableModels.map(\.id), ["plus1", "free1", "free2"])
    }

    func testWhenOnAppearThenSelectsMostPremiumAvailableModel() async {
        // "a" is advanced (non-free tier); "b" is a free-tier model. The default selection must be the most
        // premium available model, and must not be swayed by whatever was previously persisted.
        let provider = MockAIModelProvider(models: [model("b", tier: ["free"]), model("a", tier: ["plus"])])
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
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])])
        let (viewModel, _) = makeViewModel(provider: provider)

        // Select before the async fetch resolves; the load must not overwrite the user's choice with the default one.
        await wait(viewModel.$availableModels, until: { !$0.isEmpty }) {
            viewModel.onAppear()
            viewModel.select("b")
        }

        XCTAssertEqual(viewModel.selectedModelID, "b")
    }

    func testWhenSelectThenSelectionUpdatesWithoutPersisting() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"]), model("b", tier: ["free"])])
        let (viewModel, _) = makeViewModel(provider: provider)
        await wait(viewModel.$availableModels, until: { !$0.isEmpty }) {
            viewModel.onAppear()
        }

        viewModel.select("b")

        XCTAssertEqual(viewModel.selectedModelID, "b")
        XCTAssertNil(provider.updatedModelID)
    }

    func testWhenStartChatThenSelectedModelIsPersisted() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])])
        let (viewModel, _) = makeViewModel(provider: provider)
        await wait(viewModel.$selectedModelID, until: { $0 != nil }) {
            viewModel.onAppear()
        }

        viewModel.startChat()

        XCTAssertEqual(provider.updatedModelID, "a")
    }

    func testWhenStartChatThenRequestsDuckAIChatWithoutCompletingSection() async {
        let delegate = SpySectionDelegate()
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])])
        let (viewModel, _) = makeViewModel(provider: provider, delegate: delegate)
        await wait(viewModel.$selectedModelID, until: { $0 != nil }) {
            viewModel.onAppear()
        }

        viewModel.startChat()

        XCTAssertEqual(delegate.requestedChatModelIDs, ["a"])
        // Requesting the chat does not complete the section.
        XCTAssertTrue(delegate.completedSections.isEmpty)
    }

    func testWhenStartChatWithNoModelsThenChatIsRequestedWithoutASelection() async {
        let delegate = SpySectionDelegate()
        let provider = MockAIModelProvider(models: [])
        let (viewModel, prefetcher) = makeViewModel(provider: provider, delegate: delegate)
        await wait(prefetcher.$models, until: { if case .failed = $0 { return true } else { return false } }) {
            viewModel.onAppear()
        }

        viewModel.startChat()

        XCTAssertEqual(delegate.requestedChatModelIDs.count, 1)
        XCTAssertNil(delegate.requestedChatModelIDs[0])
        XCTAssertNil(provider.updatedModelID)
    }

    func testWhenTheScreenReappearsThenModelsAreKeptWithoutRefetching() async {
        let provider = MockAIModelProvider(models: [model("a", tier: ["plus"])])
        let (viewModel, _) = makeViewModel(provider: provider)
        await wait(viewModel.$availableModels, until: { !$0.isEmpty }) {
            viewModel.onAppear()
        }

        viewModel.onDisappear()
        viewModel.onAppear()

        XCTAssertEqual(viewModel.availableModels.map(\.id), ["a"])
        XCTAssertEqual(viewModel.selectedModelID, "a")
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    // MARK: - Helpers

    private func makeViewModel(provider: MockAIModelProvider,
                               delegate: SubscriptionOnboardingSectionDelegate? = nil)
    -> (viewModel: SubscriptionOnboardingDuckAIViewModel, prefetcher: SubscriptionOnboardingPrefetcher) {
        let prefetcher = SubscriptionOnboardingPrefetcher(connectionInfoService: StubConnectionInfoService(),
                                                          modelProvider: provider)
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
        await fulfillment(of: [expectation], timeout: 5)
    }
}

// MARK: - Test doubles

private struct StubConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        throw CancellationError()
    }
}

@MainActor
private final class MockAIModelProvider: SubscriptionOnboardingAIModelProviding {
    private let models: [AIChatModel]
    private(set) var fetchCallCount = 0
    private(set) var updatedModelID: String?

    init(models: [AIChatModel]) {
        self.models = models
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
    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        completedSections.append(section)
    }
    func sectionDidRequestDuckAIChat(modelID: String?) {
        requestedChatModelIDs.append(modelID)
    }
    func sectionDidRequestAdvance() {}
    func sectionDidRequestGoBack() {}
}

// MARK: - DefaultSubscriptionOnboardingAIModelProvider

/// Covers the live provider: the `/models` fetch, the tier-aware access mapping, and the persisted selection.
@MainActor
final class DefaultSubscriptionOnboardingAIModelProviderTests: XCTestCase {

    private var modelsService: StubModelsService!
    private var preferences: StubPreferences!
    private var subscriptionManager: SubscriptionManagerMock!
    private var sut: DefaultSubscriptionOnboardingAIModelProvider!

    override func setUp() {
        super.setUp()
        modelsService = StubModelsService()
        preferences = StubPreferences()
        subscriptionManager = SubscriptionManagerMock()
        sut = DefaultSubscriptionOnboardingAIModelProvider(modelsService: modelsService,
                                                          preferences: preferences,
                                                          subscriptionManager: subscriptionManager)
    }

    override func tearDown() {
        sut = nil
        subscriptionManager = nil
        preferences = nil
        modelsService = nil
        super.tearDown()
    }

    func testWhenTheFetchSucceedsThenItResolvesWithTheModels() async {
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4")]))

        let models = await sut.fetchModels()

        XCTAssertEqual(models.map(\.id), ["gpt-5.4"])
    }

    func testWhenTheFetchFailsThenItResolvesEmpty() async {
        modelsService.result = .failure(StubModelsService.StubError.fetchFailed)

        let models = await sut.fetchModels()

        XCTAssertTrue(models.isEmpty)
    }

    func testWhenThereIsNoSubscriptionThenPaidModelsAreNotAccessible() async {
        // The resolved subscription tier feeds the access mapping, which is the provider's own wiring now.
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4", accessTier: ["plus"])]))

        let models = await sut.fetchModels()

        XCTAssertEqual(models.map(\.entityHasAccess), [false])
    }

    func testWhenTheSubscriptionIsPlusThenPlusModelsAreAccessible() async {
        subscriptionManager.resultSubscription = .success(activeSubscription(tier: .plus))
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4", accessTier: ["plus"])]))

        let models = await sut.fetchModels()

        XCTAssertEqual(models.map(\.entityHasAccess), [true])
    }

    func testWhenUpdatingSelectedModelThenTheIDAndShortNameArePersisted() async {
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4")]))
        _ = await sut.fetchModels()

        sut.updateSelectedModel("gpt-5.4")

        XCTAssertEqual(preferences.selectedModelId, "gpt-5.4")
        XCTAssertEqual(preferences.selectedModelShortName, "GPT-5.4 short")
    }

    func testWhenFetchesAreSequentialThenEachMakesItsOwnRequest() async {
        // The provider doesn't cache, which is what lets the prefetcher retry once its state has gone to `.failed`.
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4")]))

        let first = await sut.fetchModels()
        let second = await sut.fetchModels()

        XCTAssertEqual(first.map(\.id), ["gpt-5.4"])
        XCTAssertEqual(second.map(\.id), ["gpt-5.4"])
        XCTAssertEqual(modelsService.fetchCallCount, 2)
    }

    // MARK: - Helpers

    private func activeSubscription(tier: TierName) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(productId: UUID().uuidString,
                               name: "Test subscription",
                               billingPeriod: .monthly,
                               startedAt: Date(),
                               expiresOrRenewsAt: Date().addingTimeInterval(60 * 60 * 24 * 30),
                               platform: .apple,
                               status: .autoRenewable,
                               activeOffers: [],
                               tier: tier,
                               availableChanges: nil,
                               pendingPlans: nil)
    }

    private func remoteModel(id: String, accessTier: [String] = []) -> AIChatRemoteModel {
        AIChatRemoteModel(id: id,
                          name: "GPT-5.4",
                          modelShortName: "GPT-5.4 short",
                          provider: "openai",
                          entityHasAccess: true,
                          supportsImageUpload: false,
                          supportedTools: [],
                          accessTier: accessTier)
    }
}

@MainActor
private final class StubModelsService: AIChatModelsProviding {
    enum StubError: Error {
        case fetchFailed
    }

    var result: Result<AIChatModelsResponse, Error> = .success(AIChatModelsResponse(models: []))
    private(set) var fetchCallCount = 0

    func fetchModels() async throws -> AIChatModelsResponse {
        fetchCallCount += 1
        return try result.get()
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
