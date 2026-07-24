//
//  OnboardingPersonalizationAppSettingsTests.swift
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

import Testing
import Foundation
@testable import DuckDuckGo

@Suite("Onboarding Personalization – App Settings adapter")
final class OnboardingPersonalizationAppSettingsTests {
    private let userDefaults: UserDefaults
    private let sut: AppUserDefaults

    // A unique suite per test instance keeps the backing UserDefaults isolated and parallel-safe.
    private let groupName = "onboarding.personalization.appsettings.\(UUID().uuidString)"

    init() throws {
        userDefaults = try #require(UserDefaults(suiteName: groupName))
        UserDefaults.app = userDefaults
        sut = AppUserDefaults(groupName: groupName)
    }

    deinit {
        UserDefaults.app = .standard
        userDefaults.removePersistentDomain(forName: groupName)
    }

    // MARK: - Recently visited sites (Search step)

    @Test("Recently visited sites defaults to On")
    func recentlyVisitedDefaultsToOn() {
        // WHEN
        let result = sut.recentlyVisitedSitesEnabled

        // THEN
        #expect(result)
    }

    @Test("Recently visited sites passes straight through to the store", arguments: [true, false])
    func recentlyVisitedPassthrough(enabled: Bool) {
        // WHEN
        sut.recentlyVisitedSitesEnabled = enabled

        // THEN
        #expect(sut.recentlyVisitedSites == enabled)
        #expect(sut.recentlyVisitedSitesEnabled == enabled)
    }

    // MARK: - Duck Player (Block Ads step)

    @Test("Duck Player defaults to Off, with DuckDuckGo Search Results On")
    func duckPlayerDefaultsToOff() {
        // THEN
        #expect(!sut.isDuckPlayerEnabled)
        #expect(sut.duckPlayerNativeYoutubeMode == .ask)   // "Let me choose"
        #expect(sut.duckPlayerNativeUISERPEnabled)          // DuckDuckGo Search Results → On
    }

    @Test("Enabling Duck Player sets Open Automatically and keeps Search Results On")
    func enablingDuckPlayer() {
        // WHEN
        sut.isDuckPlayerEnabled = true

        // THEN
        #expect(sut.isDuckPlayerEnabled)
        #expect(sut.duckPlayerNativeYoutubeMode == .auto)   // "Open Automatically"
        #expect(sut.duckPlayerNativeUISERPEnabled)          // still On in both states
    }

    @Test("Disabling Duck Player sets Let-me-choose and keeps Search Results On")
    func disablingDuckPlayer() {
        // GIVEN
        sut.isDuckPlayerEnabled = true // move off the default first

        // WHEN
        sut.isDuckPlayerEnabled = false

        // THEN
        #expect(!sut.isDuckPlayerEnabled)
        #expect(sut.duckPlayerNativeYoutubeMode == .ask)    // "Let me choose"
        #expect(sut.duckPlayerNativeUISERPEnabled)          // still On in both states
    }

    @Test("Duck Player flag reflects the underlying YouTube mode")
    func duckPlayerReflectsYoutubeMode() {
        // WHEN
        sut.duckPlayerNativeYoutubeMode = .auto
        // THEN
        #expect(sut.isDuckPlayerEnabled)

        // WHEN - any non-auto mode reads as "off"
        sut.duckPlayerNativeYoutubeMode = .never
        // THEN
        #expect(!sut.isDuckPlayerEnabled)
    }
}
