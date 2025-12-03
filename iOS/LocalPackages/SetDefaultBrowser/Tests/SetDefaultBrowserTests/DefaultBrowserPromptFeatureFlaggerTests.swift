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

    @Test("Check Remote Subfeature Settings Are Returned Correctly")
    func checkRemoteSettingsAreReturnedCorrectly() throws {
        // GIVEN
        mockFeatureFlagSettingsProvider.defaultBrowserPromptFeatureSettings = [
            DefaultBrowserPromptFeatureSettings.firstActiveModalDelayDays.rawValue: 2,
            DefaultBrowserPromptFeatureSettings.secondActiveModalDelayDays.rawValue: 4,
            DefaultBrowserPromptFeatureSettings.subsequentActiveModalRepeatIntervalDays.rawValue: 6,
            DefaultBrowserPromptFeatureSettings.inactiveModalNumberOfDaysSinceInstall.rawValue: 48,
            DefaultBrowserPromptFeatureSettings.inactiveModalNumberOfInactiveDays.rawValue: 23,
        ]
        let sut = DefaultBrowserPromptFeatureFlag(settingsProvider: mockFeatureFlagSettingsProvider)

        // WHEN
        let firstModalDelayDays = sut.firstActiveModalDelayDays
        let secondModalDelayDays = sut.secondActiveModalDelayDays
        let subsequentModalRepeatIntervalDays = sut.subsequentActiveModalRepeatIntervalDays
        let inactiveModalNumberOfDaysSinceInstall = sut.inactiveModalNumberOfDaysSinceInstall
        let inactiveModalNumberOfInactiveDays = sut.inactiveModalNumberOfInactiveDays

        // THEN
        #expect(firstModalDelayDays == 2)
        #expect(secondModalDelayDays == 4)
        #expect(subsequentModalRepeatIntervalDays == 6)
        #expect(inactiveModalNumberOfDaysSinceInstall == 48)
        #expect(inactiveModalNumberOfInactiveDays == 23)
    }

    @Test("Check Subfeature Settings Default Value Are Returned When Remote Settings Not Set")
    func checkDefaultSettingsAreReturnedWhenRemoteSettingsAreNotSet() throws {
        // GIVEN
        mockFeatureFlagSettingsProvider.defaultBrowserPromptFeatureSettings = [:]
        let sut = DefaultBrowserPromptFeatureFlag(settingsProvider: mockFeatureFlagSettingsProvider)

        // WHEN
        let firstModalDelayDays = sut.firstActiveModalDelayDays
        let secondModalDelayDays = sut.secondActiveModalDelayDays
        let subsequentModalRepeatIntervalDays = sut.subsequentActiveModalRepeatIntervalDays
        let inactiveModalNumberOfDaysSinceInstall = sut.inactiveModalNumberOfDaysSinceInstall
        let inactiveModalNumberOfInactiveDays = sut.inactiveModalNumberOfInactiveDays

        // THEN
        #expect(firstModalDelayDays == 1)
        #expect(secondModalDelayDays == 4)
        #expect(subsequentModalRepeatIntervalDays == 14)
        #expect(inactiveModalNumberOfDaysSinceInstall == 28)
        #expect(inactiveModalNumberOfInactiveDays == 7)
    }

}
