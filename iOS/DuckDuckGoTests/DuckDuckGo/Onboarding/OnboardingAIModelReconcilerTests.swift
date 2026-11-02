//
//  OnboardingAIModelReconcilerTests.swift
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
import Testing
import AIChat
import Onboarding
@_spi(Testing) import Persistence
@testable import DuckDuckGo

@MainActor
@Suite("Onboarding - AI Model Reconciler")
struct OnboardingAIModelReconcilerTests {
    private let tutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)
    private let preferences = AIChatPreferencesPersistor(keyValueStore: InMemoryKeyValueStore())
    private let providerStore: any KeyedStoring<OnboardingAIModelStoringKeys> = InMemoryKeyValueStore().keyedStoring()
    private let prefetcher = MockOnboardingAIModelsPrefetcher()

    init() {
        tutorialSettings.onboardingDownloadReason = .privateAIChat
        prefetcher.fetchedModels = [
            Self.model(id: "gpt-new", shortName: "GPT New", provider: "openai"),
            Self.model(id: "claude-new", shortName: "Claude New", provider: "anthropic"),
            Self.model(id: "claude-other", shortName: "Claude Other", provider: "anthropic"),
            Self.model(id: "llama", shortName: "Llama", provider: "meta")
        ]
    }

    // MARK: - Gating

    @available(iOS 16, macOS 13, *)
    @Test("Does not reconcile for users who didn't pick the private AI chat reason", .timeLimit(.minutes(1)), arguments: [nil, OnboardingDownloadReason.browserPrivately, .noAI, .blockAds])
    func doesNothingForOtherReasons(_ reason: OnboardingDownloadReason?) async {
        // GIVEN
        tutorialSettings.onboardingDownloadReason = reason
        preferences.selectedModelId = "claude-old"
        providerStore.selectedModelProvider = "anthropic"

        // WHEN
        await makeSUT().reconcile()

        // THEN
        #expect(prefetcher.prefetchCallCount == 0)
        #expect(preferences.selectedModelId == "claude-old")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Does not reconcile when the models fetch didn't succeed", .timeLimit(.minutes(1)))
    func doesNothingWithoutFetchedModels() async {
        // GIVEN
        prefetcher.fetchedModels = nil
        preferences.selectedModelId = "claude-old"
        providerStore.selectedModelProvider = "anthropic"

        // WHEN
        await makeSUT().reconcile()

        // THEN
        #expect(prefetcher.prefetchCallCount == 1)
        #expect(preferences.selectedModelId == "claude-old")
    }

    // MARK: - No provider stored

    @available(iOS 16, macOS 13, *)
    @Test("Back-fills the provider and keeps the model when no provider is stored and the model is available", .timeLimit(.minutes(1)))
    func backFillsProviderAndKeepsModel() async {
        // GIVEN - a model that isn't the provider's first one, e.g. changed after onboarding
        preferences.selectedModelId = "claude-other"
        preferences.selectedModelShortName = "Claude Other"

        // WHEN
        await makeSUT().reconcile()

        // THEN
        #expect(providerStore.selectedModelProvider == "anthropic")
        #expect(preferences.selectedModelId == "claude-other")
        #expect(preferences.selectedModelShortName == "Claude Other")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Does not reconcile when no provider is stored and the model is no longer available", .timeLimit(.minutes(1)))
    func doesNothingWithoutProviderWhenModelUnavailable() async {
        // GIVEN
        preferences.selectedModelId = "claude-old"

        // WHEN
        await makeSUT().reconcile()

        // THEN
        #expect(providerStore.selectedModelProvider == nil)
        #expect(preferences.selectedModelId == "claude-old")
    }

    // MARK: - Provider stored

    @available(iOS 16, macOS 13, *)
    @Test("Selects the stored provider's first available model when the stored model was replaced", .timeLimit(.minutes(1)))
    func replacesUnavailableModelWithProvidersFirstModel() async {
        // GIVEN
        preferences.selectedModelId = "claude-old"
        preferences.selectedModelShortName = "Claude Old"
        providerStore.selectedModelProvider = "anthropic"

        // WHEN
        await makeSUT().reconcile()

        // THEN
        #expect(preferences.selectedModelId == "claude-new")
        #expect(preferences.selectedModelShortName == "Claude New")
        #expect(providerStore.selectedModelProvider == "anthropic")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Selects the stored provider's first available model when no model is stored", .timeLimit(.minutes(1)))
    func selectsProvidersFirstModelWhenModelCleared() async {
        // GIVEN - e.g. Duck.ai cleared the stale model id
        providerStore.selectedModelProvider = "openai"

        // WHEN
        await makeSUT().reconcile()

        // THEN
        #expect(preferences.selectedModelId == "gpt-new")
        #expect(preferences.selectedModelShortName == "GPT New")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keeps a model picked in Duck.ai after onboarding, even from a provider onboarding doesn't offer", .timeLimit(.minutes(1)))
    func keepsModelPickedInDuckAIAfterOnboarding() async {
        // GIVEN - the user picked ChatGPT in onboarding, then switched to Llama in Duck.ai.
        // Llama's provider isn't one onboarding offers, so this also checks the model is looked up among every accessible model.
        preferences.selectedModelId = "llama"
        providerStore.selectedModelProvider = "openai"

        // WHEN
        await makeSUT().reconcile()

        // THEN - the later Duck.ai choice wins over the onboarding provider
        #expect(preferences.selectedModelId == "llama")
        #expect(providerStore.selectedModelProvider == "openai")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Does not reconcile when the stored provider has no available model", .timeLimit(.minutes(1)))
    func doesNothingWhenProviderHasNoModel() async {
        // GIVEN
        preferences.selectedModelId = "mistral-old"
        providerStore.selectedModelProvider = "mistral"

        // WHEN
        await makeSUT().reconcile()

        // THEN
        #expect(preferences.selectedModelId == "mistral-old")
    }
}

// MARK: - Helpers

private extension OnboardingAIModelReconcilerTests {

    func makeSUT() -> OnboardingAIModelReconciler {
        OnboardingAIModelReconciler(
            tutorialSettings: tutorialSettings,
            preferences: preferences,
            providerStore: providerStore,
            prefetcher: prefetcher
        )
    }

    static func model(id: String, shortName: String, provider: String) -> AIChatRemoteModel {
        AIChatRemoteModel(
            id: id,
            name: shortName,
            modelShortName: shortName,
            provider: provider,
            entityHasAccess: true,
            supportsImageUpload: false,
            supportedTools: [],
            accessTier: []
        )
    }
}
