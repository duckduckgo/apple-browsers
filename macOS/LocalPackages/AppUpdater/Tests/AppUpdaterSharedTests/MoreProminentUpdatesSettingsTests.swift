//
//  MoreProminentUpdatesSettingsTests.swift
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

import AppUpdaterShared
import FoundationExtensions
import PrivacyConfigTestsUtils
import Testing

@Suite("MoreProminentUpdatesSettings")
struct MoreProminentUpdatesSettingsTests {

    private func makeSettings(_ json: String?, isInternalUser: Bool = false) -> MoreProminentUpdatesSettings {
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.subfeatureSettings = json
        return MoreProminentUpdatesSettings(privacyConfig: privacyConfig, isInternalUser: isInternalUser)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Uses the external defaults when the subfeature has no settings", .timeLimit(.minutes(1)))
    func externalDefaultsWithoutSettings() {
        let settings = makeSettings(nil)

        #expect(settings.firstPromptDelay == .hours(48))
        #expect(settings.secondPromptDelay == .hours(96))
        #expect(settings.appStoreUpdateAvailableDelay == .hours(24))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Uses the internal defaults for internal users when the subfeature has no settings", .timeLimit(.minutes(1)))
    func internalDefaultsWithoutSettings() {
        let settings = makeSettings(nil, isInternalUser: true)

        #expect(settings.firstPromptDelay == .hours(2))
        #expect(settings.secondPromptDelay == .hours(4))
        #expect(settings.appStoreUpdateAvailableDelay == .hours(1))
    }

    private static let allValues = """
        {"hoursUntilFirstPrompt": 72, "hoursUntilSecondPrompt": 120, "hoursUntilAppStoreUpdateAvailable": 12,
         "internalHoursUntilFirstPrompt": 0.5, "internalHoursUntilSecondPrompt": 3, "internalHoursUntilAppStoreUpdateAvailable": 0}
        """

    @available(iOS 16, macOS 13, *)
    @Test("External users read the unprefixed values", .timeLimit(.minutes(1)))
    func externalUsersReadUnprefixedValues() {
        let settings = makeSettings(Self.allValues)

        #expect(settings == MoreProminentUpdatesSettings(hoursUntilFirstPrompt: 72, hoursUntilSecondPrompt: 120, hoursUntilAppStoreUpdateAvailable: 12))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Internal users read the internal values", .timeLimit(.minutes(1)))
    func internalUsersReadInternalValues() {
        let settings = makeSettings(Self.allValues, isInternalUser: true)

        #expect(settings == MoreProminentUpdatesSettings(hoursUntilFirstPrompt: 0.5, hoursUntilSecondPrompt: 3, hoursUntilAppStoreUpdateAvailable: 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Internal users fall back to the internal defaults when only the external values are present", .timeLimit(.minutes(1)))
    func internalUsersIgnoreExternalValues() {
        let settings = makeSettings(#"{"hoursUntilFirstPrompt": 72, "hoursUntilSecondPrompt": 120, "hoursUntilAppStoreUpdateAvailable": 12}"#,
                                    isInternalUser: true)

        #expect(settings == MoreProminentUpdatesSettings(.internal))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Falls back per value when one setting is missing or negative", .timeLimit(.minutes(1)))
    func fallsBackPerValue() {
        let settings = makeSettings(#"{"hoursUntilSecondPrompt": 100, "hoursUntilAppStoreUpdateAvailable": -1}"#)

        #expect(settings == MoreProminentUpdatesSettings(hoursUntilFirstPrompt: 48, hoursUntilSecondPrompt: 100, hoursUntilAppStoreUpdateAvailable: 24))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Falls back to both default prompt timings when the second prompt would come before the first", .timeLimit(.minutes(1)))
    func fallsBackWhenPromptsAreOutOfOrder() {
        let settings = makeSettings(#"{"hoursUntilFirstPrompt": 72, "hoursUntilSecondPrompt": 60, "hoursUntilAppStoreUpdateAvailable": 12}"#)

        #expect(settings == MoreProminentUpdatesSettings(hoursUntilFirstPrompt: 48, hoursUntilSecondPrompt: 96, hoursUntilAppStoreUpdateAvailable: 12))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Falls back to the defaults when the settings can't be decoded", .timeLimit(.minutes(1)))
    func fallsBackForUndecodableSettings() {
        let settings = makeSettings(#"{"hoursUntilFirstPrompt": "soon"}"#)

        #expect(settings == MoreProminentUpdatesSettings(.external))
    }
}
