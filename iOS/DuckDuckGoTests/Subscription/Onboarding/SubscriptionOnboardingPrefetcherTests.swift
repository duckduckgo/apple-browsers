//
//  SubscriptionOnboardingPrefetcherTests.swift
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
final class SubscriptionOnboardingPrefetcherTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Connection info

    func testWhenFetchConnectionInfoIfNeededSucceedsThenStateIsLoaded() async {
        let info = SubscriptionOnboardingConnectionInfo(ip: "31.120.130.50", city: "Madrid", country: "ES")
        let service = MockConnectionInfoService(result: .success(info))
        let prefetcher = makePrefetcher(connectionInfoService: service)

        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
        }

        XCTAssertEqual(prefetcher.connectionInfo, .loaded(info))
    }

    func testWhenFetchConnectionInfoIfNeededFailsThenStateIsFailed() async {
        let service = MockConnectionInfoService(result: .failure)
        let prefetcher = makePrefetcher(connectionInfoService: service)

        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
        }

        XCTAssertEqual(prefetcher.connectionInfo, .failed)
    }

    func testWhenFetchConnectionInfoIfNeededIsCalledTwiceThenFetchesOnce() async {
        let service = MockConnectionInfoService(result: .success(.init(ip: "1.2.3.4", city: "Paris", country: "FR")))
        let prefetcher = makePrefetcher(connectionInfoService: service)

        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
            prefetcher.fetchConnectionInfoIfNeeded()
        }

        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func testWhenFetchConnectionInfoIfNeededIsCalledAfterFailureThenRetries() async {
        let service = MockConnectionInfoService(result: .failure)
        let prefetcher = makePrefetcher(connectionInfoService: service)

        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
        }
        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
        }

        XCTAssertEqual(service.fetchCallCount, 2)
    }

    // MARK: - Models

    func testWhenFetchModelsIfNeededSucceedsThenStateIsLoaded() async {
        let models = [model("a"), model("b")]
        let provider = MockAIModelProvider(models: models)
        let prefetcher = makePrefetcher(modelProvider: provider)

        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
        }

        XCTAssertEqual(loadedModelIDs(prefetcher.models), ["a", "b"])
    }

    func testWhenFetchModelsIfNeededReturnsNoModelsThenStateIsFailed() async {
        let provider = MockAIModelProvider(models: [])
        let prefetcher = makePrefetcher(modelProvider: provider)

        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
        }

        assertFailed(prefetcher.models)
    }

    func testWhenFetchModelsIfNeededIsCalledTwiceThenFetchesOnce() async {
        let provider = MockAIModelProvider(models: [model("a")])
        let prefetcher = makePrefetcher(modelProvider: provider)

        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
            prefetcher.fetchModelsIfNeeded()
        }

        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    func testWhenFetchModelsIfNeededIsCalledAfterFailureThenRetries() async {
        let provider = MockAIModelProvider(models: [])
        let prefetcher = makePrefetcher(modelProvider: provider)

        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
        }
        provider.models = [model("a")]
        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
        }

        XCTAssertEqual(provider.fetchCallCount, 2)
        XCTAssertEqual(loadedModelIDs(prefetcher.models), ["a"])
    }

    // MARK: - prefetch()

    func testWhenPrefetchThenBothConnectionInfoAndModelsAreFetched() async {
        let service = MockConnectionInfoService(result: .success(.init(ip: "1.2.3.4", city: "Paris", country: "FR")))
        let provider = MockAIModelProvider(models: [model("a")])
        let prefetcher = makePrefetcher(connectionInfoService: service, modelProvider: provider)

        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.prefetch()
        }

        XCTAssertEqual(service.fetchCallCount, 1)
        XCTAssertEqual(provider.fetchCallCount, 1)
    }

    // MARK: - Passthroughs

    func testWhenReadingPersistedModelIDThenValueComesFromProvider() {
        let provider = MockAIModelProvider(models: [], persistedModelID: "gpt-5.4")
        let prefetcher = makePrefetcher(modelProvider: provider)

        XCTAssertEqual(prefetcher.persistedModelID, "gpt-5.4")
    }

    func testWhenUpdatingSelectedModelThenValueIsForwardedToProvider() {
        let provider = MockAIModelProvider(models: [])
        let prefetcher = makePrefetcher(modelProvider: provider)

        prefetcher.updateSelectedModel("claude-sonnet-4.6")

        XCTAssertEqual(provider.updatedModelID, "claude-sonnet-4.6")
    }

    // MARK: - Helpers

    private func makePrefetcher(connectionInfoService: SubscriptionOnboardingConnectionInfoService = MockConnectionInfoService(result: .failure),
                                modelProvider: SubscriptionOnboardingAIModelProviding = MockAIModelProvider(models: [])) -> SubscriptionOnboardingPrefetcher {
        SubscriptionOnboardingPrefetcher(connectionInfoService: connectionInfoService, modelProvider: modelProvider)
    }

    private func model(_ id: String) -> AIChatModel {
        AIChatModel(id: id, name: "Model", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"])
    }

    /// `AIChatModel` isn't `Equatable`, so `FetchState<[AIChatModel]>` can't use `XCTAssertEqual` directly —
    /// compare the fetched models by id instead.
    private func loadedModelIDs(_ state: SubscriptionOnboardingPrefetcher.FetchState<[AIChatModel]>) -> [String]? {
        guard case .loaded(let models) = state else { return nil }
        return models.map(\.id)
    }

    private func assertFailed<T>(_ state: SubscriptionOnboardingPrefetcher.FetchState<T>,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        guard case .failed = state else {
            XCTFail("Expected .failed", file: file, line: line)
            return
        }
    }

    /// Runs `trigger`, then waits until `publisher` emits a value satisfying `predicate`. Mirrors the helper
    /// in the VPN/Duck.ai activation view model tests: the fetches are async, so results arrive on a later
    /// run-loop turn.
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

private extension SubscriptionOnboardingPrefetcher.FetchState {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

private final class MockConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    enum Result {
        case success(SubscriptionOnboardingConnectionInfo)
        case failure
    }

    private let result: Result
    private(set) var fetchCallCount = 0

    init(result: Result) {
        self.result = result
    }

    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        fetchCallCount += 1
        switch result {
        case .success(let info): return info
        case .failure: throw URLError(.badServerResponse)
        }
    }
}

@MainActor
private final class MockAIModelProvider: SubscriptionOnboardingAIModelProviding {
    var models: [AIChatModel]
    var persistedModelID: String?
    private(set) var fetchCallCount = 0
    private(set) var updatedModelID: String?

    nonisolated init(models: [AIChatModel], persistedModelID: String? = nil) {
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
