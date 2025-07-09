//
//  DefaultBrowserAndDockPromptFeatureFlaggerTests.swift
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
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

struct DefaultBrowserAndDockPromptFeatureFlaggerTests {
    let privacyConfigManagerMock = MockPrivacyConfigurationManager()
    let featureFlaggerMock = MockFeatureFlagger()

    @Test("Check Feature Flag Returns The Correct Value", arguments: [true, false])
    func isDefaultBrowserAndDockPromptFeatureEnabledThenReturnTheCorrectValue(_ isEnabled: Bool) {
        // GIVEN
        featureFlaggerMock.enabledFeatureFlags = isEnabled ? [.scheduledSetDefaultBrowserAndAddToDockPrompts] : []
        let sut = DefaultBrowserAndDockPromptFeatureFlag(privacyConfigManager: privacyConfigManagerMock, featureFlagger: featureFlaggerMock)

        // WHEN
        let result = sut.isDefaultBrowserAndDockPromptFeatureEnabled

        // THEN
        #expect(result == isEnabled)
    }

    @Test("Check Remote Subfeature Settings Are Returned Correctly")
    func checkRemoteSettingsAreReturnedCorrectly() throws {
        // GIVEN
        let privacyConfigMock = privacyConfigManagerMock.privacyConfig as! MockPrivacyConfiguration
        privacyConfigMock.featureSettings = [
            DefaultBrowserAndDockPromptFeatureSettings.firstPopoverDelayDays.rawValue: 2,
            DefaultBrowserAndDockPromptFeatureSettings.bannerAfterPopoverDelayDays.rawValue: 4,
            DefaultBrowserAndDockPromptFeatureSettings.bannerRepeatIntervalDays.rawValue: 6
        ]
        let sut = DefaultBrowserAndDockPromptFeatureFlag(privacyConfigManager: privacyConfigManagerMock, featureFlagger: featureFlaggerMock)

        // WHEN
        let firstPopoverDelayDays = sut.firstPopoverDelayDays
        let bannerAfterPopoverDelayDays = sut.bannerAfterPopoverDelayDays
        let bannerRepeatIntervalDays = sut.bannerRepeatIntervalDays

        // THEN
        #expect(firstPopoverDelayDays == 2)
        #expect(bannerAfterPopoverDelayDays == 4)
        #expect(bannerRepeatIntervalDays == 6)
    }

    @Test("Check Subfeature Settings Default Value Are Returned When Remote Settings Not Set")
    func checkDefaultSettingsAreReturnedWhenRemoteSettingsAreNotSet() throws {
        // GIVEN
        let privacyConfigMock = privacyConfigManagerMock.privacyConfig as! MockPrivacyConfiguration
        privacyConfigMock.featureSettings = [:]
        let sut = DefaultBrowserAndDockPromptFeatureFlag(privacyConfigManager: privacyConfigManagerMock, featureFlagger: featureFlaggerMock)

        // WHEN
        let firstPopoverDelayDays = sut.firstPopoverDelayDays
        let bannerAfterPopoverDelayDays = sut.bannerAfterPopoverDelayDays
        let bannerRepeatIntervalDays = sut.bannerRepeatIntervalDays

        // THEN
        #expect(firstPopoverDelayDays == 14)
        #expect(bannerAfterPopoverDelayDays == 14)
        #expect(bannerRepeatIntervalDays == 14)
    }

}
