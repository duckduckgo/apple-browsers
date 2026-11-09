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
import PrivacyConfigTestsUtils
import Core
import Testing
@testable import DuckDuckGo

@Suite("Onboarding - AI Models Fallback")
struct OnboardingAIModelsFallbackTests {

    // The baked last-resort list, restated independently so a change to it is caught here.
    private enum BakedDefault {
        static let ids = ["gpt-5.4-nano", "claude-haiku-4-5", "mistral-small-2603"]
        static let providers: [OnboardingAIProvider] = [.openai, .anthropic, .mistral]
        static let defaultModelId = "gpt-5.4-nano"
    }

    // Distinct from the baked default so we can tell the config was actually used.
    static let supportedAIModelsJSON = """
        { "defaultModelId": "config-openai", "models": [{"id": "config-openai", "provider": "openai", "modelShortName": "Config GPT"}, {"id": "config-claude", "provider": "anthropic", "modelShortName": "Config Claude"}] }
        """

    static let modelsWithUnsupportedProviderJSON = """
    { "defaultModelId": "o", "models": [{"id": "o", "provider": "openai", "modelShortName": "O"}, {"id": "t", "provider": "tinfoil", "modelShortName": "T"}] }
    """

    static let modelsWithAllUnsupportedProviderJSON = """
    { "defaultModelId": "o", "models": [{"id": "t0", "provider": "tinfoil", "modelShortName": "T0"}, {"id": "t1", "provider": "tinfoil", "modelShortName": "T1"}] }
    """

    private func makeSUT(settingsJSON: String?) -> OnboardingAIModelsFallback {
        let privacyConfig = PrivacyConfigurationMock()
        if let settingsJSON, let value = try? JSONSerialization.jsonObject(with: Data(settingsJSON.utf8), options: .fragmentsAllowed) {
            privacyConfig.settings[.iOSBrowserConfig] = ["onboardingAIModelsFallback": value]
        }
        let manager = PrivacyConfigurationManagerMock()
        manager.privacyConfig = privacyConfig
        return OnboardingAIModelsFallback(privacyConfigurationManager: manager)
    }

    @Test("Check valid config settings are decoded and used")
    func validConfigIsUsed() {
        // GIVEN
        let sut = makeSUT(settingsJSON: Self.supportedAIModelsJSON)

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
        let sut = makeSUT(settingsJSON: Self.modelsWithUnsupportedProviderJSON)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == ["o"])
        #expect(result.defaultModelId == "o")
    }

    @Test("Check a malformed model entry is dropped, the rest kept")
    func malformedEntryIsDropped() {
        // GIVEN the second entry has a numeric id and the third is missing its provider
        let sut = makeSUT(settingsJSON: """
            { "defaultModelId": "o", "models": [{"id": "o", "provider": "openai"}, {"id": 1, "provider": "anthropic"}, {"id": "m"}] }
            """)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == ["o"])
        #expect(result.defaultModelId == "o")
    }

    @Test("Check a default id not among the kept models falls back to the OpenAI model")
    func unknownDefaultFallsBackToOpenAIModel() {
        // GIVEN the default points at a model dropped for its unsupported provider
        let sut = makeSUT(settingsJSON: """
            { "defaultModelId": "t", "models": [{"id": "c", "provider": "anthropic"}, {"id": "o", "provider": "openai"}, {"id": "t", "provider": "tinfoil"}] }
            """)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == ["c", "o"])
        #expect(result.defaultModelId == "o")
    }

    @Test("Check a default id not among the kept models falls back to the first model when there is no OpenAI model")
    func unknownDefaultWithoutOpenAIFallsBackToFirstModel() {
        // GIVEN no OpenAI model and a default that isn't in the list
        let sut = makeSUT(settingsJSON: """
            { "defaultModelId": "missing", "models": [{"id": "c", "provider": "anthropic"}, {"id": "m", "provider": "mistral"}] }
            """)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == ["c", "m"])
        #expect(result.defaultModelId == "c")
    }

    @Test("Check settings that are not an object fall back to the baked default")
    func malformedConfigFallsBackToBaked() {
        // GIVEN
        let sut = makeSUT(settingsJSON: #""not-an-object""#)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == BakedDefault.ids)
        #expect(result.models.map(\.provider) == BakedDefault.providers)
        #expect(result.defaultModelId == BakedDefault.defaultModelId)
    }

    @Test("Check settings whose models are not an array fall back to the baked default")
    func malformedModelsFallsBackToBaked() {
        // GIVEN models encoded as a string instead of an array
        let sut = makeSUT(settingsJSON: #"{ "defaultModelId": "x", "models": "[{\"id\":\"x\",\"provider\":\"openai\"}]" }"#)

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
        let sut = makeSUT(settingsJSON: nil)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == BakedDefault.ids)
        #expect(result.models.map(\.provider) == BakedDefault.providers)
        #expect(result.defaultModelId == BakedDefault.defaultModelId)
    }

    @Test("Check the remote config entry is parsed into the fallback models")
    func remoteConfigEntryIsParsed() throws {
        // GIVEN the iOSBrowserConfig settings as shipped in the remote privacy config
        let configJSON = """
        {
            "features": {
                "iOSBrowserConfig": {
                    "state": "enabled",
                    "exceptions": [],
                    "settings": {
                        "onboardingAIModelsFallback": {
                            "defaultModelId": "gpt-5.4-nano",
                            "models": [
                                { "id": "gpt-5.4-nano", "provider": "openai", "modelShortName": "5.4-nano" },
                                { "id": "claude-haiku-4-5", "provider": "anthropic", "modelShortName": "Haiku 4.5" },
                                { "id": "mistral-small-2603", "provider": "mistral", "modelShortName": "Mistral" }
                            ]
                        }
                    },
                    "features": {}
                }
            },
            "unprotectedTemporary": []
        }
        """
        let configData = try PrivacyConfigurationData(data: Data(configJSON.utf8))
        let manager = PrivacyConfigurationManagerMock()
        manager.privacyConfig = AppPrivacyConfiguration(data: configData,
                                                        identifier: "",
                                                        localProtection: MockDomainsProtectionStore(),
                                                        internalUserDecider: DefaultInternalUserDecider(store: InternalUserStore()))
        let sut = OnboardingAIModelsFallback(privacyConfigurationManager: manager)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == ["gpt-5.4-nano", "claude-haiku-4-5", "mistral-small-2603"])
        #expect(result.models.map(\.provider) == [.openai, .anthropic, .mistral])
        #expect(result.models.map(\.modelShortName) == ["5.4-nano", "Haiku 4.5", "Mistral"])
        #expect(result.defaultModelId == "gpt-5.4-nano")
    }

    @Test("Check config entries with all unsupported providers fallback to last resort")
    func allUnsupportedProviderFallbackToLastResort() {
        // GIVEN
        let sut = makeSUT(settingsJSON: Self.modelsWithAllUnsupportedProviderJSON)

        // WHEN
        let result = sut.aiModels

        // THEN
        #expect(result.models.map(\.id) == BakedDefault.ids)
        #expect(result.models.map(\.provider) == BakedDefault.providers)
        #expect(result.defaultModelId == BakedDefault.defaultModelId)
    }
}
