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

    func testWhenUpdatingSelectedModelThenValueIsForwardedToProvider() {
        let provider = MockAIModelProvider(models: [])
        let prefetcher = makePrefetcher(modelProvider: provider)

        prefetcher.updateSelectedModel("claude-sonnet-4.6")

        XCTAssertEqual(provider.updatedModelID, "claude-sonnet-4.6")
    }

    // MARK: - Cancellation

    func testWhenConnectionInfoFetchIsCancelledMidFlightThenStateResetsToIdle() async {
        let service = MockConnectionInfoService(result: .success(.init(ip: "1.2.3.4", city: "Paris", country: "FR")))
        service.cancelsInFlight = true
        let prefetcher = makePrefetcher(connectionInfoService: service)

        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
        }

        XCTAssertEqual(prefetcher.connectionInfo, .idle)
    }

    func testWhenConnectionInfoFetchIsCancelledMidFlightThenALaterFetchCanStart() async {
        let info = SubscriptionOnboardingConnectionInfo(ip: "31.120.130.50", city: "Madrid", country: "ES")
        let service = MockConnectionInfoService(result: .success(info))
        service.cancelsInFlight = true
        let prefetcher = makePrefetcher(connectionInfoService: service)
        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
        }

        service.cancelsInFlight = false
        await wait(prefetcher.$connectionInfo, until: { !$0.isLoading }) {
            prefetcher.fetchConnectionInfoIfNeeded()
        }

        XCTAssertEqual(service.fetchCallCount, 2)
        XCTAssertEqual(prefetcher.connectionInfo, .loaded(info))
    }

    func testWhenModelsFetchIsCancelledMidFlightThenStateResetsToIdle() async {
        let provider = MockAIModelProvider(models: [model("a")])
        provider.cancelsInFlight = true
        let prefetcher = makePrefetcher(modelProvider: provider)

        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
        }

        assertIdle(prefetcher.models)
    }

    func testWhenModelsFetchIsCancelledMidFlightThenALaterFetchCanStart() async {
        let provider = MockAIModelProvider(models: [model("gpt-5.4")])
        provider.cancelsInFlight = true
        let prefetcher = makePrefetcher(modelProvider: provider)
        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
        }

        provider.cancelsInFlight = false
        await wait(prefetcher.$models, until: { !$0.isLoading }) {
            prefetcher.fetchModelsIfNeeded()
        }

        XCTAssertEqual(provider.fetchCallCount, 2)
        XCTAssertEqual(loadedModelIDs(prefetcher.models), ["gpt-5.4"])
    }

    // MARK: - Deallocation

    func testWhenPrefetcherIsReleasedMidFetchThenItDeallocates() async {
        let service = MockConnectionInfoService(result: .success(.init(ip: "1.2.3.4", city: "Paris", country: "FR")))
        service.isGated = true
        weak var weakPrefetcher: SubscriptionOnboardingPrefetcher?

        var prefetcher: SubscriptionOnboardingPrefetcher? = makePrefetcher(connectionInfoService: service)
        weakPrefetcher = prefetcher
        prefetcher?.fetchConnectionInfoIfNeeded()
        await waitUntil({ service.fetchCallCount == 1 }, description: "the fetch to reach the service")

        prefetcher = nil

        XCTAssertNil(weakPrefetcher)
        service.releaseGate()
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

    private func assertIdle<T>(_ state: SubscriptionOnboardingPrefetcher.FetchState<T>,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        guard case .idle = state else {
            XCTFail("Expected .idle", file: file, line: line)
            return
        }
    }

    /// Runs `trigger`, then waits until `publisher` emits a value satisfying `predicate` — the fetches are
    /// async, so results arrive on a later run-loop turn. Unlike the view-model tests' equivalent this skips
    /// the replayed current value, since `.idle` already satisfies predicates like `!isLoading`.
    private func wait<T>(_ publisher: Published<T>.Publisher,
                         until predicate: @escaping (T) -> Bool,
                         trigger: () -> Void) async {
        let expectation = expectation(description: "publisher satisfies predicate")
        var fulfilled = false
        publisher
            // `@Published` replays its current value on subscribe, which for these states is `.idle` — and
            // `.idle` satisfies predicates like `!isLoading`, fulfilling before `trigger` has even run.
            .dropFirst()
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

/// `@MainActor` so `fetchCallCount` is never touched from two threads at once — the prefetcher awaits this
/// off the main actor. `init` stays `nonisolated` so it can be a default argument.
@MainActor
private final class MockConnectionInfoService: SubscriptionOnboardingConnectionInfoService {
    enum Result {
        case success(SubscriptionOnboardingConnectionInfo)
        case failure
    }

    private let result: Result
    private(set) var fetchCallCount = 0

    var cancelsInFlight = false

    /// When set, `fetchConnectionInfo()` parks until ``releaseGate()``, so a test can keep a fetch in flight.
    var isGated = false
    private var gate: CheckedContinuation<Void, Never>?

    nonisolated init(result: Result) {
        self.result = result
    }

    func fetchConnectionInfo() async throws -> SubscriptionOnboardingConnectionInfo {
        fetchCallCount += 1
        if cancelsInFlight {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        if isGated {
            await withCheckedContinuation { gate = $0 }
        }
        switch result {
        case .success(let info): return info
        case .failure: throw URLError(.badServerResponse)
        }
    }

    func releaseGate() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
private final class MockAIModelProvider: SubscriptionOnboardingAIModelProviding {
    var models: [AIChatModel]
    private(set) var fetchCallCount = 0
    private(set) var updatedModelID: String?

    var cancelsInFlight = false

    nonisolated init(models: [AIChatModel]) {
        self.models = models
    }

    func fetchModels() async -> [AIChatModel] {
        fetchCallCount += 1
        if cancelsInFlight {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return models
    }

    func updateSelectedModel(_ modelID: String) {
        updatedModelID = modelID
    }
}
