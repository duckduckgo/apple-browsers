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

/// Covers the live adapter over ``UTIModelStore``: the `onModelsUpdated` → async bridge and the two
/// pass-through members. Stubs the store's own dependencies, matching how the other `UTIModelStore`
/// consumers are tested.
@MainActor
final class DefaultSubscriptionOnboardingAIModelProviderTests: XCTestCase {

    private var modelsService: StubModelsService!
    private var preferences: StubPreferences!
    private var sut: DefaultSubscriptionOnboardingAIModelProvider!

    override func setUp() {
        super.setUp()
        modelsService = StubModelsService()
        preferences = StubPreferences()
        sut = DefaultSubscriptionOnboardingAIModelProvider(modelsService: modelsService,
                                                          preferences: preferences,
                                                          subscriptionManager: SubscriptionManagerMock())
    }

    override func tearDown() {
        // Unblocks any gated fetch so a parked stub doesn't outlive the test.
        modelsService?.releaseGate()
        sut = nil
        preferences = nil
        modelsService = nil
        super.tearDown()
    }

    func testWhenStoreNotifiesThenFetchResolvesWithItsModels() async {
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4")]))

        let models = await sut.fetchModels()

        XCTAssertEqual(models.map(\.id), ["gpt-5.4"])
    }

    func testWhenStoreFetchFailsThenFetchResolvesEmpty() async {
        modelsService.result = .failure(StubModelsService.StubError.fetchFailed)

        let models = await sut.fetchModels()

        XCTAssertTrue(models.isEmpty)
    }

    func testWhenUpdatingSelectedModelThenItPersistsAsANewChatSelection() {
        sut.updateSelectedModel("gpt-5.4")

        XCTAssertEqual(preferences.selectedModelId, "gpt-5.4")
    }

    func testWhenTwoFetchesOverlapThenBothResolveFromOneStoreFetch() async {
        // The store has a single callback slot, so before coalescing the later fetch overwrote the earlier
        // one's callback and left it suspended forever.
        modelsService.isGated = true
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4")]))

        async let first = sut.fetchModels()
        async let second = sut.fetchModels()

        // Wait until both callers have actually queued — asserting on `fetchCallCount` alone would only prove
        // the first one arrived, leaving the second's registration to task-scheduling order.
        await waitUntil({ self.modelsService.fetchCallCount == 1 && self.sut.pendingCallerCount == 2 },
                        description: "both callers to queue on one store fetch")
        modelsService.releaseGate()

        let (firstModels, secondModels) = await (first, second)

        XCTAssertEqual(firstModels.map(\.id), ["gpt-5.4"])
        XCTAssertEqual(secondModels.map(\.id), ["gpt-5.4"])
        // One underlying fetch served both callers.
        XCTAssertEqual(modelsService.fetchCallCount, 1)
    }

    func testWhenTwoFetchesAreSequentialThenEachStartsItsOwnStoreFetch() async {
        // The counterpart to the overlapping case: the adapter coalesces in-flight callers but does not
        // cache, so a call made after the previous one resolved refetches. That is what lets the prefetcher
        // retry once its state has gone to `.failed`.
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4")]))

        let first = await sut.fetchModels()
        let second = await sut.fetchModels()

        XCTAssertEqual(first.map(\.id), ["gpt-5.4"])
        XCTAssertEqual(second.map(\.id), ["gpt-5.4"])
        XCTAssertEqual(modelsService.fetchCallCount, 2)
    }

    func testWhenCallerIsCancelledThenItResolvesWithoutWaitingForTheTimeout() async {
        // Gated with no release, so the store never notifies and only the cancellation can resolve this.
        modelsService.isGated = true
        let task = Task { await sut.fetchModels() }
        await waitUntil({ self.modelsService.fetchCallCount == 1 }, description: "the store fetch to start")

        let start = Date()
        task.cancel()
        let models = await task.value

        XCTAssertTrue(models.isEmpty)
        // Without the cancellation handler this would park for the full `fetchTimeout`.
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testWhenOneOfTwoCallersIsCancelledThenTheOtherStillGetsTheModels() async {
        modelsService.isGated = true
        modelsService.result = .success(AIChatModelsResponse(models: [remoteModel(id: "gpt-5.4")]))

        let cancelled = Task { await sut.fetchModels() }
        await waitUntil({ self.modelsService.fetchCallCount == 1 }, description: "the store fetch to start")
        async let survivor = sut.fetchModels()
        // Both queued before cancelling, so the survivor can't miss the shared fetch and start its own.
        await waitUntil({ self.sut.pendingCallerCount == 2 }, description: "the survivor to queue")

        cancelled.cancel()
        _ = await cancelled.value
        modelsService.releaseGate()

        // Cancelling one caller must not resolve the other with an empty list.
        let survivorModels = await survivor
        XCTAssertEqual(survivorModels.map(\.id), ["gpt-5.4"])
    }

    // MARK: - Helpers

    /// Polls `condition` on the main actor, failing rather than hanging if it never becomes true.
    private func waitUntil(_ condition: @MainActor () -> Bool,
                           description: String,
                           file: StaticString = #filePath,
                           line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }

    private func remoteModel(id: String) -> AIChatRemoteModel {
        AIChatRemoteModel(id: id,
                          name: "GPT-5.4",
                          provider: "openai",
                          entityHasAccess: true,
                          supportsImageUpload: false,
                          supportedTools: [],
                          accessTier: [])
    }
}

@MainActor
private final class StubModelsService: AIChatModelsProviding {
    enum StubError: Error {
        case fetchFailed
    }

    var result: Result<AIChatModelsResponse, Error> = .success(AIChatModelsResponse(models: []))

    /// When set, `fetchModels()` parks until ``releaseGate()``, so a test can hold one fetch in flight
    /// while it starts another.
    var isGated = false
    private(set) var fetchCallCount = 0
    private var gate: CheckedContinuation<Void, Never>?

    func fetchModels() async throws -> AIChatModelsResponse {
        fetchCallCount += 1
        if isGated {
            await withCheckedContinuation { gate = $0 }
        }
        return try result.get()
    }

    func releaseGate() {
        gate?.resume()
        gate = nil
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
