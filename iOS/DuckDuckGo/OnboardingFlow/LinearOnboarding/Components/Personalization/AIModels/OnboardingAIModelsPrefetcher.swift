//
//  OnboardingAIModelsPrefetcher.swift
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

// MARK: - Model

enum OnboardingAIProvider: String, CaseIterable {
    case anthropic
    case openai
    case mistral
}

struct OnboardingAIModelOption: Identifiable, Equatable {
    let id: String
    let provider: OnboardingAIProvider
    let modelShortName: String?
}

struct OnboardingAIModelResponse: Equatable {
    let models: [OnboardingAIModelOption]
    let defaultModelId: String?
}

// MARK: - Prefetcher

@MainActor
protocol OnboardingAIModelsPrefetching {
    var resolvedModel: OnboardingAIModelResponse { get }

    @discardableResult
    func prefetch() -> Task<Void, Never>
}

/// Fetches the AI models ahead of the picker step so its options are ready when the view appears
/// (avoids a loading state and the bubble resize that comes with late-arriving content).
///
/// `prefetch()` is kicked off when the user picks the `.privateAIChat` reason — a couple of screens
/// before the model step — and the result is read synchronously via `resolvedModel`. If the fetch
/// isn't finished (or failed), `resolvedModel` returns the fallback list, so callers never wait.
@MainActor
final class OnboardingAIModelsPrefetcher: OnboardingAIModelsPrefetching {
    // The service to fetch the AIChatModels from
    private let service: AIChatModelsProviding
    // The fallback providing AI models in case the service fails
    private let fallback: OnboardingAIModelsFallbackProviding
    // Resolve the AI Chat Models according to the Onboarding requirements
    private let resolver: ([AIChatRemoteModel]) -> OnboardingAIModelResponse

    // The current in-flight fetch, if any. Calls while one is running share it instead of starting another
    private var inFlight: Task<Void, Never>?

    // The mapped result, computed once when the fetch completes.
    private var resolved: OnboardingAIModelResponse?

    var resolvedModel: OnboardingAIModelResponse {
        resolved ?? fallback.aiModels
    }

    init(
        service: AIChatModelsProviding = AIChatModelsService(),
        fallback: OnboardingAIModelsFallbackProviding = OnboardingAIModelsFallback(),
        resolver: @escaping ([AIChatRemoteModel]) -> OnboardingAIModelResponse = OnboardingAIModelsResolver.resolve
    ) {
        self.service = service
        self.fallback = fallback
        self.resolver = resolver
    }
    
    /// Prefetch the AI Models shown in the Onboarding flow. If the fetch fails, the fallback list is used instead.
    ///
    /// Fire-and-forget in production — the result is read synchronously via `resolvedModel`. The
    /// `Task` is returned only so tests can `await` completion before asserting.
    ///
    /// - Returns: The in-flight prefetch `Task`.
    @discardableResult
    func prefetch() -> Task<Void, Never> {
        if let inFlight { return inFlight }

        let task = Task { [weak self, service] in
            guard let self else { return }
            defer { self.inFlight = nil }
            do {
                let apiModels = try await service.fetchModels().models
                let resolved = self.resolver(apiModels)
                // If the fetch resolves to zero usable models, fall back.
                self.resolved = resolved.models.isEmpty ? self.fallback.aiModels : resolved
            } catch {
                self.resolved = self.fallback.aiModels
            }
        }
        inFlight = task
        return task
    }
}

// MARK: - Private

enum OnboardingAIModelsResolver {

    /// Maps raw models to options (accessible only, one per provider in first-appearance order) and
    /// picks the default (OpenAI, falling back to the first available).
    static func resolve(from models: [AIChatRemoteModel]) -> OnboardingAIModelResponse {
        let aiModels = models
            .filter(\.entityHasAccess)
            .compactMap(OnboardingAIModelOption.init)

        let modelsByProvider = Dictionary(grouping: aiModels, by: \.provider)

        // Grouped Dictionary has different order for keys so we maintain the order based on the Provider definition
        let modelsToReturn = OnboardingAIProvider.allCases
            .compactMap { modelsByProvider[$0]?.first }

        // Prefer the OpenAI model as default, otherwise the first model shown (display order)
        let defaultProviderId = modelsByProvider[OnboardingAIProvider.openai]?.first?.id ?? modelsToReturn.first?.id

        return OnboardingAIModelResponse(models: modelsToReturn, defaultModelId: defaultProviderId)
    }

}

// MARK: - OnboardingAIModelOption + AIChatRemoteModel

extension OnboardingAIModelOption {

    init?(_ value: AIChatRemoteModel) {
        guard let provider = OnboardingAIProvider(rawValue: value.provider) else { return nil }
        self.init(id: value.id, provider: provider, modelShortName: value.modelShortName)
    }

}
