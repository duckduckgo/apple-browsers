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
import PrivacyConfigTestsUtils
import Testing

@Suite("MoreProminentUpdatesSettings")
struct MoreProminentUpdatesSettingsTests {

    private func makeSettings(_ json: String?) -> MoreProminentUpdatesSettings {
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.subfeatureSettings = json
        return MoreProminentUpdatesSettings(privacyConfig: privacyConfig)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Uses defaults when the subfeature has no settings", .timeLimit(.minutes(1)))
    func defaultsWithoutSettings() {
        let settings = makeSettings(nil)

        #expect(settings.daysUntilFirstPrompt == 2)
        #expect(settings.daysUntilSecondPrompt == 4)
        #expect(settings.versionsBehindBeforePrompt == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reads all values from the remote settings", .timeLimit(.minutes(1)))
    func readsRemoteValues() {
        let settings = makeSettings(#"{"daysUntilFirstPrompt": 3, "daysUntilSecondPrompt": 7, "versionsBehindBeforePrompt": 2}"#)

        #expect(settings.daysUntilFirstPrompt == 3)
        #expect(settings.daysUntilSecondPrompt == 7)
        #expect(settings.versionsBehindBeforePrompt == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Falls back per value when one setting is missing", .timeLimit(.minutes(1)))
    func fallsBackForMissingValue() {
        let settings = makeSettings(#"{"daysUntilSecondPrompt": 10}"#)

        #expect(settings.daysUntilFirstPrompt == 2)
        #expect(settings.daysUntilSecondPrompt == 10)
        #expect(settings.versionsBehindBeforePrompt == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Falls back when a value is negative", .timeLimit(.minutes(1)))
    func fallsBackForNegativeValue() {
        let settings = makeSettings(#"{"daysUntilFirstPrompt": -1, "daysUntilSecondPrompt": 5}"#)

        #expect(settings.daysUntilFirstPrompt == 2)
        #expect(settings.daysUntilSecondPrompt == 5)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Falls back when the settings can't be decoded", .timeLimit(.minutes(1)), arguments: [
        #"{"daysUntilFirstPrompt": "soon"}"#,
        #"{"versionsBehindBeforePrompt": "one"}"#
    ])
    func fallsBackForInvalidSettings(json: String) {
        let settings = makeSettings(json)

        #expect(settings == MoreProminentUpdatesSettings())
    }

    @available(iOS 16, macOS 13, *)
    @Test("Validates the versions-behind threshold", .timeLimit(.minutes(1)), arguments: [-1, 0, 3])
    func validatesVersionsBehindBeforePrompt(value: Int) {
        let settings = makeSettings("{\"daysUntilFirstPrompt\": 3, \"versionsBehindBeforePrompt\": \(value)}")

        #expect(settings.daysUntilFirstPrompt == 3)
        #expect(settings.versionsBehindBeforePrompt == (value < 0 ? 1 : value))
    }
}
