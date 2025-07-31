//
//  FirefoxHistoryReaderTests.swift
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
import Common
@testable import DuckDuckGo_Privacy_Browser

struct FirefoxHistoryReaderTests {

    private let tld = TLD()

    @Test("Check if expected frecent sites are read from Firefox history database")
    func readingFrecentSites() throws {
        let historyReader = FirefoxHistoryReader(firefoxDataDirectoryURL: resourceURL(), tld: tld)
        let frecentSites = try historyReader.readFrecentSites().get()

        #expect(frecentSites.count == 5)

        let firstSite = try #require(frecentSites.first)
        #expect(firstSite.url == "https://spreadprivacy.com/")
        #expect(firstSite.title == "Spread Privacy")
        #expect(firstSite.frecency == 2075)
        #expect(firstSite.lastVisitDate == 1669241488218952)
    }

    @Test("Check if frecent site with search host is filtered out of frecent sites")
    func frecentSearchHost_NotInFrecentSites() throws {
        let historyReader = FirefoxHistoryReader(firefoxDataDirectoryURL: resourceURL(), tld: tld)
        let frecentSites = try historyReader.readFrecentSites().get()

        #expect(!frecentSites.contains(where: { $0.url == "https://duckduckgo.com" }))
    }

    @Test("Check if subdomain of frecent site with search host is not filtered out of frecent sites")
    func frecentSearchHostSubdomain_InFrecentSites() throws {
        let historyReader = FirefoxHistoryReader(firefoxDataDirectoryURL: resourceURL(), tld: tld)
        let frecentSites = try historyReader.readFrecentSites().get()

        #expect(frecentSites.contains(where: { $0.url == "https://start.duckduckgo.com" }))
    }

    @Test("Check if frecent search shortcut has expected shortcut URL")
    func frecentSearchSite_UsesSearchShortcutURL() throws {
        let historyReader = FirefoxHistoryReader(firefoxDataDirectoryURL: resourceURL(), tld: tld)
        let frecentSites = try historyReader.readFrecentSites().get()

        let searchSite = try #require(frecentSites.first { $0.url.contains("amazon.com") })
        #expect(searchSite.url == "https://amazon.com")
        #expect(searchSite.title == "Amazon.com : ducks")
    }

    @Test("Check if frecent site containing search shortcut string has expected shortcut URL")
    func frecentSiteWithSearchSiteString_UsesOriginalShortcutURL() throws {
        let historyReader = FirefoxHistoryReader(firefoxDataDirectoryURL: resourceURL(), tld: tld)
        let frecentSites = try historyReader.readFrecentSites().get()

        let site = try #require(frecentSites.first { $0.url.contains("amazon.example.com") })
        #expect(site.url == "https://amazon.example.com/?s=baidu")
    }

}

private extension FirefoxHistoryReaderTests {

    func resourceURL() -> URL {
        let bundle = Bundle(for: FirefoxBookmarksReaderTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData")
    }
}
