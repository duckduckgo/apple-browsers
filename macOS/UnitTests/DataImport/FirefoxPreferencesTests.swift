//
//  FirefoxPreferencesTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

class FirefoxPreferencesTests {

    @Test("Check if default new tab favorites setting is parsed from preferences")
    func whenPreferencesAreParsed_withNoTopSiteUserPref_newTabFavoritesEnabledIsTrue() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        #expect(preferences.newTabFavoritesEnabled == true)
    }

    @Test("Check if new tab favorites setting is parsed from preferences")
    func whenPreferencesAreParsed_withTopSiteUserPref_newTabFavoritesEnabledHasExpectedValue() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL(withAlternatePrefs: true))
        #expect(preferences.newTabFavoritesEnabled == false)
    }

    @Test("Check if default pinned sites are parsed from preferences")
    func whenPreferencesAreParsed_withNoPinnedUserPref_newTabPinnedSitesHasExpectedSites() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL(withAlternatePrefs: true))
        let pinnedSites = preferences.newTabPinnedSites

        #expect(pinnedSites.isEmpty)
    }

    @Test("Check if pinned sites are parsed from preferences")
    func whenPreferencesAreParsed_withPinnedUserPref_newTabPinnedSitesHasExpectedSites() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        let pinnedSites = preferences.newTabPinnedSites

        #expect(pinnedSites.count == 7)
        #expect(pinnedSites.compacted().count == 4)

        let firstPinnedSite = try #require(pinnedSites.compacted().first)
        #expect(firstPinnedSite.url == "https://duckduckgo.com/")
        #expect(firstPinnedSite.label == "DuckDuckGo")
    }

    @Test("Check if default favorites count is parsed from preferences")
    func whenPreferencesAreParsed_withNoTopSitesRowsOrSponsoredSitesUserPrefs_newTabFavoritesCountHasExpectedValue() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL(withAlternatePrefs: true))
        #expect(preferences.newTabFavoritesCount == 5)
    }

    @Test("Check if favorites count is parsed from preferences")
    func whenPreferencesAreParsed_withTopSitesRowsAndSponsoredSitesUserPrefs_newTabFavoritesCountHasExpectedValue() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        #expect(preferences.newTabFavoritesCount == 16)
    }

    @Test("Check if default blocked sites are parsed from preferences")
    func whenPreferencesAreParsed_withNoBlockedUserPref_isURLBlockedOnNewTabReturnsFalse_forProvidedSite() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL(withAlternatePrefs: true))
        let siteURL = "https://www.mozilla.org/privacy/firefox/"
        let isBlocked = preferences.isURLBlockedOnNewTab(siteURL)
        #expect(isBlocked == false)
    }

    @Test("Check if blocked sites are parsed from preferences")
    func whenPreferencesAreParsed_withBlockedUserPref_isURLBlockedOnNewTabReturnsTrue_forBlockedSite() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        let siteURL = "https://www.mozilla.org/privacy/firefox/"
        let isBlocked = preferences.isURLBlockedOnNewTab(siteURL)
        #expect(isBlocked == true)
    }

}

private extension FirefoxPreferencesTests {
    static let altPrefsDir = "/Alternate prefs"

    func resourceURL(withAlternatePrefs: Bool = false) -> URL {
        let bundle = Bundle(for: FirefoxPreferencesTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData")
            .appendingPathComponent(withAlternatePrefs ? Self.altPrefsDir : "")
    }

}
