//
//  PromptCooldownIntervalProviderTests.swift
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
import BrowserServicesKit
import BrowserServicesKitTestsUtils
@testable import DuckDuckGo

@Suite("Modal Prompt Coordination - Cooldown Interval Provider")
final class PromptCooldownIntervalProviderTests {
    private var privacyConfigManagerMock: MockPrivacyConfigurationManager
    private var sut: PromptCooldownIntervalProvider!

    init() {
        privacyConfigManagerMock = MockPrivacyConfigurationManager()
        sut = PromptCooldownIntervalProvider(privacyConfigManager: privacyConfigManagerMock)
    }

    @Test("Check Default Cooldown Interval Is 24 Hours When No Remote Config Is Set")
    func whenNoRemoteConfigThenDefaultCooldownIntervalIs24Hours() {
        // GIVEN
        privacyConfigManagerMock.privacyConfig = MockPrivacyConfiguration()

        // WHEN
        let result = sut.cooldownInterval

        // THEN
        #expect(result == 24)
    }

    @Test(
        "Check Cooldown Interval Uses Remote Config Value When Available",
        arguments: [
            12,
            24,
            48,
            72
        ]
    )
    func whenRemoteConfigIsSetThenCooldownIntervalUsesRemoteValue(remoteValue: Int) {
        // GIVEN
        let mockPrivacyConfig = MockPrivacyConfiguration()
        mockPrivacyConfig.featureSettings = [PromptCooldownIntervalSettings.promptCooldownInterval.rawValue: remoteValue]
        privacyConfigManagerMock.privacyConfig = mockPrivacyConfig

        // WHEN
        let result = sut.cooldownInterval

        // THEN
        #expect(result == remoteValue)
    }

    @Test("Check Default Value Is Returned When Remote Config Contains Invalid Type")
    func whenRemoteConfigContainsInvalidTypeThenDefaultValueIsReturned() {
        // GIVEN
        let mockPrivacyConfig = MockPrivacyConfiguration()
        mockPrivacyConfig.featureSettings = [PromptCooldownIntervalSettings.promptCooldownInterval.rawValue: "invalid_string"]
        privacyConfigManagerMock.privacyConfig = mockPrivacyConfig

        // WHEN
        let result = sut.cooldownInterval

        // THEN
        #expect(result == 24)
    }

    @Test("Check Default Value Is Returned When Remote Config Is Empty")
    func whenRemoteConfigIsEmptyThenDefaultValueIsReturned() {
        // GIVEN
        let mockPrivacyConfig = MockPrivacyConfiguration()
        mockPrivacyConfig.featureSettings = [:]
        privacyConfigManagerMock.privacyConfig = mockPrivacyConfig

        // WHEN
        let result = sut.cooldownInterval

        // THEN
        #expect(result == 24)
    }
}
