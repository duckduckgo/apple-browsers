//
//  OnboardingAIModelsResolverTests.swift
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

@Suite("Onboarding - AI Models Resolver")
struct OnboardingAIModelsResolverTests {

    private func model(id: String, provider: String, hasAccess: Bool = true, shortName: String? = nil) -> AIChatRemoteModel {
        AIChatRemoteModel(
            id: id,
            name: id,
            modelShortName: shortName,
            provider: provider,
            entityHasAccess: hasAccess,
            supportsImageUpload: false,
            supportedTools: [],
            accessTier: []
        )
    }

    @Test("Check models the entity has no access to are dropped")
    func dropsInaccessibleModels() {
        // WHEN
        let result = OnboardingAIModelsResolver.resolve(from: [
            model(id: "openai-yes", provider: "openai", hasAccess: true),
            model(id: "anthropic-no", provider: "anthropic", hasAccess: false)
        ])

        // THEN
        #expect(result.models.map(\.id) == ["openai-yes"])
    }

    @Test("Check models from unsupported providers are dropped")
    func dropsUnsupportedProviders() {
        // WHEN
        let result = OnboardingAIModelsResolver.resolve(from: [
            model(id: "openai", provider: "openai"),
            model(id: "tinfoil", provider: "tinfoil"),
            model(id: "google", provider: "google")
        ])

        // THEN
        #expect(result.models.map(\.id) == ["openai"])
    }

    @Test("Check only the first accessible model per provider is kept, in appearance order")
    func onePerProviderFirstInAppearanceOrder() {
        // WHEN
        let result = OnboardingAIModelsResolver.resolve(from: [
            model(id: "openai-1", provider: "openai"),
            model(id: "openai-2", provider: "openai")
        ])

        // THEN
        #expect(result.models.map(\.id) == ["openai-1"])
    }

    @Test("Check providers are returned in display order (Claude, ChatGPT, Mistral) regardless of input order")
    func ordersByProviderDisplayOrder() {
        // WHEN
        let result = OnboardingAIModelsResolver.resolve(from: [
            model(id: "mistral", provider: "mistral"),
            model(id: "openai", provider: "openai"),
            model(id: "anthropic", provider: "anthropic")
        ])

        // THEN
        #expect(result.models.map(\.provider) == [.anthropic, .openai, .mistral])
        #expect(result.models.map(\.id) == ["anthropic", "openai", "mistral"])
    }

    @Test("Check default is the OpenAI model when present")
    func defaultIsOpenAIWhenPresent() {
        // WHEN
        let result = OnboardingAIModelsResolver.resolve(from: [
            model(id: "anthropic", provider: "anthropic"),
            model(id: "openai", provider: "openai"),
            model(id: "mistral", provider: "mistral")
        ])

        // THEN
        #expect(result.defaultModelId == "openai")
    }

    @Test("Check default falls back to the first model shown when OpenAI is absent")
    func defaultFallsBackToFirstShownWhenNoOpenAI() {
        // WHEN
        let result = OnboardingAIModelsResolver.resolve(from: [
            model(id: "mistral", provider: "mistral"),
            model(id: "anthropic", provider: "anthropic")
        ])

        // THEN default is the first model in display order (Claude before Mistral) regardless of input order.
        #expect(result.defaultModelId == "anthropic")
    }

    @Test("Check empty input yields no models and no default")
    func emptyInput() {
        let result = OnboardingAIModelsResolver.resolve(from: [])

        #expect(result.models.isEmpty)
        #expect(result.defaultModelId == nil)
    }
}
