//
//  OnboardingAIModelsFallbackTests.swift
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
import PrivacyConfig
import Testing
@testable import DuckDuckGo

@Suite("Onboarding - AI Models Fallback")
struct OnboardingAIModelsFallbackTests {

    // The baked last-resort list, restated independently so a change to it is caught here.
    private enum BakedDefault {
        static let ids = ["claude-haiku-4-5", "gpt-5.4-nano", "mistral-small-2603"]
        static let providers: [OnboardingAIProvider] = [.anthropic, .openai, .mistral]
        static let defaultModelId = "gpt-5.4-nano"
    }

    // Distinct from the baked default so we can tell the config was actually used/
    static let supportedAIModelsJSON = """
        { "defaultModelId": "config-openai", "models": [
            { "id": "config-openai", "provider": "openai", "modelShortName": "Config GPT" },
            { "id": "config-claude", "provider": "anthropic", "modelShortName": "Config Claude" }
        ] }
        """

    static let modelsWithUnsupportedProviderJSON = """
    { "defaultModelId": "o", "models": [
        { "id": "o", "provider": "openai", "modelShortName": "O" },
        { "id": "t", "provider": "tinfoil", "modelShortName": "T" }
    ] }
    """

    private func makeSUT(subfeatureSettings: String?) -> OnboardingAIModelsFallback {
        let privacyConfig = PrivacyConfigurationMock()
        if let subfeatureSettings {
            privacyConfig.subfeatureSettings[iOSBrowserConfigSubfeature.onboardingFlowByDownloadReasonExperiment.rawValue] = subfeatureSettings
        }
        let manager = PrivacyConfigurationManagerMock()
        manager.privacyConfig = privacyConfig
        return OnboardingAIModelsFallback(privacyConfigurationManager: manager)
    }

    @Test("Check valid config settings are decoded and used")
    func validConfigIsUsed() {
        // GIVEN
        let sut = makeSUT(subfeatureSettings: Self.supportedAIModelsJSON)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == ["config-openai", "config-claude"])
        #expect(result.models.map(\.provider) == [.openai, .anthropic])
        #expect(result.defaultModelId == "config-openai")
    }

    @Test("Check config entries with an unsupported provider are dropped, the rest kept")
    func unsupportedProviderIsDropped() {
        // GIVEN
        let sut = makeSUT(subfeatureSettings: Self.modelsWithUnsupportedProviderJSON)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == ["o"])
        #expect(result.defaultModelId == "o")
    }

    @Test("Check malformed config settings fall back to the baked default")
    func malformedConfigFallsBackToBaked() {
        // GIVEN
        let sut = makeSUT(subfeatureSettings: "{ not valid json")

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == BakedDefault.ids)
        #expect(result.models.map(\.provider) == BakedDefault.providers)
        #expect(result.defaultModelId == BakedDefault.defaultModelId)
    }

    @Test("Absent config settings fall back to the baked default")
    func absentConfigFallsBackToBaked() {
        // GIVEN
        let sut = makeSUT(subfeatureSettings: nil)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == BakedDefault.ids)
        #expect(result.models.map(\.provider) == BakedDefault.providers)
        #expect(result.defaultModelId == BakedDefault.defaultModelId)
    }
}
