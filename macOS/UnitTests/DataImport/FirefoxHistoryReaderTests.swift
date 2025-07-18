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
@testable import DuckDuckGo_Privacy_Browser

struct FirefoxHistoryReaderTests {

    @Test("Check if expected frecent sites are read from Firefox history database")
    func readingFrecentSites() async throws {
        let historyReader = FirefoxHistoryReader(firefoxDataDirectoryURL: resourceURL())
        let frecentSites = try historyReader.readFrecentSites().get()

        #expect(frecentSites.count == 2)

        let firstSite = try #require(frecentSites.first)
        #expect(firstSite.url == "https://spreadprivacy.com/")
        #expect(firstSite.title == "Spread Privacy")
        #expect(firstSite.frecency == 2075)
        #expect(firstSite.lastVisitDate == 1669241488218952)
    }

}

private extension FirefoxHistoryReaderTests {

    func resourceURL() -> URL {
        let bundle = Bundle(for: FirefoxBookmarksReaderTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData")
    }
}
