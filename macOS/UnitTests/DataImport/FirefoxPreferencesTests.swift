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

    @Test("Check if new tab favorites setting is parsed from preferences")
    func whenPreferencesAreParsed_newTabFavoritesEnabledHasExpectedValue() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        #expect(preferences.newTabFavoritesEnabled == true)
    }

    @Test("Check if pinned sites are parsed from preferences")
    func whenPreferencesAreParsed_newTabPinnedSitesHasExpectedSites() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        let pinnedSites = preferences.newTabPinnedSites

        #expect(pinnedSites.count == 7)
        #expect(pinnedSites.compacted().count == 4)

        let firstPinnedSite = try #require(pinnedSites.compacted().first)
        #expect(firstPinnedSite.url == "https://duckduckgo.com/")
        #expect(firstPinnedSite.label == "DuckDuckGo")
    }

    @Test("Check if favorites count is parsed from preferences")
    func whenPreferencesAreParsed_newTabFavoritesCountHasExpectedValue() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        #expect(preferences.newTabFavoritesCount == 16)
    }

    @Test("Check if blocked sites are parsed from preferences")
    func whenPreferencesAreParsed_isURLBlockedOnNewTabReturnsExpectedValue_forBlockedSite() throws {
        let preferences = try FirefoxPreferences(profileURL: resourceURL())
        let siteURL = "https://www.mozilla.org/privacy/firefox/"
        let isBlocked = preferences.isURLBlockedOnNewTab(siteURL)
        #expect(isBlocked)
    }

}

private extension FirefoxPreferencesTests {

    func resourceURL() -> URL {
        let bundle = Bundle(for: FirefoxPreferencesTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData")
    }

}
