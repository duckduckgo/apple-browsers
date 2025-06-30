//
//  DefaultBrowserPromptFeatureFlaggerTests.swift
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

import Foundation
import Testing
import SetDefaultBrowserTestSupport
@testable import SetDefaultBrowserCore

@Suite("Set Default Browser - Prompt Feature Flag")
struct DefaultBrowserPromptFeatureFlaggerTests {
    let mockFeatureFlagSettingsProvider = MockDefaultBrowserPromptFeatureFlagSettingsProvider()
    let mockFeatureFlagProvider = MockDefaultBrowserPromptFeatureFlagProvider()

    @Test("Check Feature Flag Returns The Correct Value", arguments: [true, false])
    func isDefaultBrowserPromptFeatureEnabledThenReturnTheCorrectValue(_ isEnabled: Bool) {
        // GIVEN
        mockFeatureFlagProvider.isDefaultBrowserPromptsFeatureEnabled = isEnabled
        let sut = DefaultBrowserPromptFeatureFlag(settingsProvider: mockFeatureFlagSettingsProvider, featureFlagProvider: mockFeatureFlagProvider)

        // WHEN
        let result = sut.isDefaultBrowserPromptsFeatureEnabled

        // THEN
        #expect(result == isEnabled)
    }

    @Test("Check Remote Subfeature Settings Are Returned Correctly")
    func checkRemoteSettingsAreReturnedCorrectly() throws {
        // GIVEN
        mockFeatureFlagSettingsProvider.featureSettings = [
            DefaultBrowserPromptFeatureSettings.firstModalDelayDays.rawValue: 2,
            DefaultBrowserPromptFeatureSettings.secondModalDelayDays.rawValue: 4,
            DefaultBrowserPromptFeatureSettings.subsequentModalRepeatIntervalDays.rawValue: 6
        ]
        let sut = DefaultBrowserPromptFeatureFlag(settingsProvider: mockFeatureFlagSettingsProvider, featureFlagProvider: mockFeatureFlagProvider)

        // WHEN
        let firstModalDelayDays = sut.firstModalDelayDays
        let secondModalDelayDays = sut.secondModalDelayDays
        let subsequentModalRepeatIntervalDays = sut.subsequentModalRepeatIntervalDays

        // THEN
        #expect(firstModalDelayDays == 2)
        #expect(secondModalDelayDays == 4)
        #expect(subsequentModalRepeatIntervalDays == 6)
    }

    @Test("Check Subfeature Settings Default Value Are Returned When Remote Settings Not Set")
    func checkDefaultSettingsAreReturnedWhenRemoteSettingsAreNotSet() throws {
        // GIVEN
        mockFeatureFlagSettingsProvider.featureSettings = [:]
        let sut = DefaultBrowserPromptFeatureFlag(settingsProvider: mockFeatureFlagSettingsProvider, featureFlagProvider: mockFeatureFlagProvider)

        // WHEN
        let firstModalDelayDays = sut.firstModalDelayDays
        let secondModalDelayDays = sut.secondModalDelayDays
        let subsequentModalRepeatIntervalDays = sut.subsequentModalRepeatIntervalDays

        // THEN
        #expect(firstModalDelayDays == 1)
        #expect(secondModalDelayDays == 4)
        #expect(subsequentModalRepeatIntervalDays == 14)
    }

}
