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
import WebExtensions
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

    // MARK: - Cookie pop-up protection (Block Ads step)

    @Test("Disabling cookie protection collapses the preference to off and clears pop-ups-without-opt-outs")
    func disablingCookieProtection() {
        // GIVEN pop-ups-without-opt-outs is on (preference == .max)
        sut.isPopUpsWithoutOptOutsEnabled = true
        #expect(sut.cookiePopupPreference == .max)

        // WHEN protection is turned off
        sut.isCookiePopUpProtectionEnabled = false

        // THEN protection is off and the child collapses with it
        #expect(!sut.isCookiePopUpProtectionEnabled)
        #expect(!sut.isPopUpsWithoutOptOutsEnabled)
        #expect(sut.cookiePopupPreference == .off)
    }

    @Test("Enabling cookie protection selects the default level, pop-ups-without-opt-outs off")
    func enablingCookieProtection() {
        // GIVEN protection is off
        sut.isCookiePopUpProtectionEnabled = false
        #expect(sut.cookiePopupPreference == .off)

        // WHEN protection is turned on
        sut.isCookiePopUpProtectionEnabled = true

        // THEN
        #expect(sut.isCookiePopUpProtectionEnabled)
        #expect(!sut.isPopUpsWithoutOptOutsEnabled)
        #expect(sut.cookiePopupPreference == .default)
    }

    @Test("Enabling pop-ups-without-opt-outs raises the preference to max, protection stays on")
    func enablingPopUpsWithoutOptOuts() {
        // WHEN
        sut.isPopUpsWithoutOptOutsEnabled = true

        // THEN
        #expect(sut.isPopUpsWithoutOptOutsEnabled)
        #expect(sut.isCookiePopUpProtectionEnabled)
        #expect(sut.cookiePopupPreference == .max)
    }

    @Test("Disabling pop-ups-without-opt-outs drops to the default level, protection stays on")
    func disablingPopUpsWithoutOptOuts() {
        // GIVEN preference == .max
        sut.isPopUpsWithoutOptOutsEnabled = true

        // WHEN
        sut.isPopUpsWithoutOptOutsEnabled = false

        // THEN
        #expect(!sut.isPopUpsWithoutOptOutsEnabled)
        #expect(sut.isCookiePopUpProtectionEnabled)
        #expect(sut.cookiePopupPreference == .default)
    }

    @Test("Cookie toggles reflect the underlying preference", arguments: [
        (CookiePopupPreference.off, false, false),
        (CookiePopupPreference.default, true, false),
        (CookiePopupPreference.max, true, true)
    ])
    func cookieTogglesReflectPreference(preference: CookiePopupPreference, protectionOn: Bool, optOutOn: Bool) {
        // WHEN
        sut.cookiePopupPreference = preference

        // THEN
        #expect(sut.isCookiePopUpProtectionEnabled == protectionOn)
        #expect(sut.isPopUpsWithoutOptOutsEnabled == optOutOn)
    }
}
