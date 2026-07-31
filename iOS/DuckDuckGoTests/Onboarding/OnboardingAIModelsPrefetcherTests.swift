//
//  OnboardingAIModelsPrefetcherTests.swift
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

import Foundation
import AIChat
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Onboarding - AI Models Prefetcher")
struct OnboardingAIModelsPrefetcherTests {

    private func makeSUT(
        service: MockAIChatModelsService = MockAIChatModelsService(),
        fallback: OnboardingAIModelsFallbackProviding = StubOnboardingAIModelsFallback(aiModels: fallbackResponse),
        resolver: @escaping ([AIChatRemoteModel]) -> OnboardingAIModelResponse = { _ in apiResponse }
    ) -> OnboardingAIModelsPrefetcher {
        OnboardingAIModelsPrefetcher(service: service, fallback: fallback, resolver: resolver)
    }

    @available(iOS 16, *)
    @Test("Check resolvedModel returns the fallback before prefetch has run", .timeLimit(.minutes(1)))
    func resolvedModelIsFallbackBeforePrefetch() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        let result = sut.resolvedModel

        // THEN
        #expect(result.models.map(\.id) == ["fallback-model"])
        #expect(result.defaultModelId == "fallback-model")
    }

    @available(iOS 16, *)
    @Test("Check resolvedModel returns the fallback while the fetch is still in flight", .timeLimit(.minutes(1)))
    func resolvedModelIsFallbackWhileInFlight() {
        // GIVEN
        let service = MockAIChatModelsService()
        service.behavior = .neverCompletes
        let sut = makeSUT(service: service)

        // WHEN
        let task = sut.prefetch()

        // THEN
        #expect(sut.resolvedModel.models.map(\.id) == ["fallback-model"])
        task.cancel() // stop the never-completing fetch
    }

    @available(iOS 16, *)
    @Test("Check a successful prefetch passes the fetched models through the resolver", .timeLimit(.minutes(1)))
    func successPassesFetchedModelsThroughResolver() async {
        // GIVEN
        var didCallResolver = false
        let service = MockAIChatModelsService()
        service.behavior = .success([remoteModel(id: "from-service", provider: "openai")])
        let sut = makeSUT(service: service, resolver: { _ in
            didCallResolver = true
            return OnboardingAIModelResponse(models: [], defaultModelId: nil)
        })

        // WHEN
        await sut.prefetch().value

        // THEN the fetched model reached the resolver and its output was stored
        #expect(didCallResolver)
    }

    @available(iOS 16, *)
    @Test("Check a failed prefetch resolves to the fallback", .timeLimit(.minutes(1)))
    func failureResolvesToFallback() async {
        // GIVEN
        let service = MockAIChatModelsService()
        service.behavior = .failure(NSError(domain: #function, code: 0, userInfo: nil))
        let sut = makeSUT(service: service)

        // WHEN
        await sut.prefetch().value

        // THEN
        #expect(sut.resolvedModel.models.map(\.id) == ["fallback-model"])
    }

    @available(iOS 16, *)
    @Test("Check concurrent prefetch calls share a single fetch", .timeLimit(.minutes(1)))
    func concurrentCallsShareOneFetch() async {
        // GIVEN
        let service = MockAIChatModelsService()
        service.behavior = .success([])
        let sut = makeSUT(service: service)

        // WHEN
        let first = sut.prefetch()
        let second = sut.prefetch()

        // THEN
        #expect(first == second) // same task → deduped
        await first.value
        #expect(service.fetchCallCount == 1)
    }

    @available(iOS 16, *)
    @Test("Check a prefetch after the previous one finished starts a fresh fetch", .timeLimit(.minutes(1)))
    func prefetchAfterCompletionRefetches() async {
        // GIVEN
        let service = MockAIChatModelsService()
        service.behavior = .success([])
        let sut = makeSUT(service: service)

        // WHEN
        await sut.prefetch().value

        // THEN
        #expect(service.fetchCallCount == 1)

        // WHEN inFlight was cleared on completion, so a second call fetches again (retry left to the caller).
        await sut.prefetch().value

        // THEN
        #expect(service.fetchCallCount == 2)
    }
}

// MARK: - Fixtures

private let fallbackResponse = OnboardingAIModelResponse(
    models: [OnboardingAIModelOption(id: "fallback-model", provider: .openai, modelShortName: "Fallback")],
    defaultModelId: "fallback-model"
)

private let apiResponse = OnboardingAIModelResponse(
    models: [OnboardingAIModelOption(id: "api-model", provider: .anthropic, modelShortName: "API")],
    defaultModelId: "api-model"
)

private func remoteModel(id: String, provider: String) -> AIChatRemoteModel {
    AIChatRemoteModel(
        id: id,
        name: id,
        provider: provider,
        entityHasAccess: true,
        supportsImageUpload: false,
        supportedTools: [],
        accessTier: []
    )
}

// MARK: - Test doubles

@MainActor
private final class MockAIChatModelsService: AIChatModelsProviding {
    enum Behavior {
        case success([AIChatRemoteModel])
        case failure(Error)
        case neverCompletes
    }

    var behavior: Behavior = .success([])
    private(set) var fetchCallCount = 0

    // `AIChatModelsProviding` is `@MainActor`, so this type is main-actor isolated and its `init` is
    // too. Default-argument expressions are evaluated in a nonisolated context (even though the suite
    // is `@MainActor`), so a `nonisolated init` is required to construct it as a default argument.
    nonisolated init() {}

    func fetchModels() async throws -> AIChatModelsResponse {
        fetchCallCount += 1
        switch behavior {
        case .success(let models):
            return AIChatModelsResponse(models: models)
        case .failure(let error):
            throw error
        case .neverCompletes:
            try await Task.sleep(nanoseconds: .max)
            return AIChatModelsResponse(models: [])
        }
    }
}

private struct StubOnboardingAIModelsFallback: OnboardingAIModelsFallbackProviding {
    let aiModels: OnboardingAIModelResponse
}
