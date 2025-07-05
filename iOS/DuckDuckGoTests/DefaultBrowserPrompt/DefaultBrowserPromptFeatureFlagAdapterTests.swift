//
//  DefaultBrowserPromptFeatureFlagAdapterTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Testing
import Core
import BrowserServicesKit
import BrowserServicesKitTestsUtils
@testable import DuckDuckGo

@Suite("Default Browser Prompt - Feature Flag Adapter")
struct DefaultBrowserPromptFeatureFlagAdapterTests {
    private var featureFlaggerMock = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider())
    private var privacyConfigurationManagerMock = MockPrivacyConfigurationManager()

    @Test("Check Method Is Forwarded To Feature Flagger")
    func checkIsFeatureOnIsForwardedToFeatureFlagger() {
        // GIVEN
        featureFlaggerMock.enabledFeatureFlags = [.scheduledSetDefaultBrowserPrompts]
        let sut = DefaultBrowserPromptFeatureFlagAdapter(featureFlagger: featureFlaggerMock, privacyConfigurationManager: privacyConfigurationManagerMock)

        // WHEN
        let result = sut.isDefaultBrowserPromptsFeatureEnabled

        // THEN
        #expect(result)
    }

    @Test("Check Method is Dispatched To Feature Flagger")
    func checkMethodIsDispatchedToPrivacyConfigurationManager() throws {
        // GIVEN
        let privacyConfig = try #require(privacyConfigurationManagerMock.privacyConfig as? MockPrivacyConfiguration)
        privacyConfig.featureSettings = ["Test": 1]
        let sut = DefaultBrowserPromptFeatureFlagAdapter(featureFlagger: featureFlaggerMock, privacyConfigurationManager: privacyConfigurationManagerMock)

        // WHEN
        let result = sut.defaultBrowserPromptFeatureSettings

        // THEN
        #expect(result.count == 1)
        #expect(result["Test"] as? Int == 1)
    }
}
