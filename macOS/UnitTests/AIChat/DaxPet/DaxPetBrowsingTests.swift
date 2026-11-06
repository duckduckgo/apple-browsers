//
//  DaxPetBrowsingTests.swift
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

import History
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DaxPetBrowsingTests: XCTestCase {

    /// `Visit.historyEntry` is weak, so fixtures must keep their entries alive.
    private var retainedEntries: [HistoryEntry] = []

    override func tearDown() {
        retainedEntries = []
        super.tearDown()
    }

    func testPagesMatchingMoreOfTheWordsComeFirstThenTheNewest() {
        let visits = [
            visit("https://a.example/", title: "Rust ownership", at: 300),
            visit("https://b.example/", title: "Rust ownership and borrowing", at: 100),
            visit("https://c.example/borrowing", title: "Lending money", at: 200),
            visit("https://d.example/", title: "Something else", at: 400)
        ]

        let ranked = DaxPetBrowser.rank(visits, matching: ["rust", "borrowing"], limit: 10)

        XCTAssertEqual(ranked.map(\.title), ["Rust ownership and borrowing", "Rust ownership", "Lending money"])
    }

    func testEachPageIsListedOnceAtItsLatestVisit() {
        let visits = [
            visit("https://a.example/", title: "Recipes", at: 100),
            visit("https://a.example/", title: "Recipes", at: 500),
            visit("https://a.example/", title: "Recipes", at: 300)
        ]

        let ranked = DaxPetBrowser.rank(visits, matching: ["recipe"], limit: 10)

        XCTAssertEqual(ranked.map(\.date), [Date(timeIntervalSince1970: 500)])
    }

    func testWithoutWordsToSearchForNothingIsFound() {
        let visits = [visit("https://a.example/", title: "Anything", at: 1)]

        XCTAssertEqual(DaxPetBrowser.rank(visits, matching: [" ", ""], limit: 10), [])
    }

    func testOnlyAsManyPagesAsAskedForAreFound() {
        let visits = (1...5).map { visit("https://s\($0).example/", title: "Duck \($0)", at: TimeInterval($0)) }

        XCTAssertEqual(DaxPetBrowser.rank(visits, matching: ["duck"], limit: 2).map(\.title), ["Duck 5", "Duck 4"])
    }

    func testATermMatchesWhenAllItsWordsAreThereInAnyOrder() {
        XCTAssertTrue(DaxPetBrowser.mentions("Le Creuset Signature Round Dutch Oven", "le creuset dutch oven"))
        XCTAssertTrue(DaxPetBrowser.mentions("Café de Flore", "cafe"))
        XCTAssertFalse(DaxPetBrowser.mentions("Le Creuset Signature Round Casserole", "le creuset dutch oven"))
        XCTAssertFalse(DaxPetBrowser.mentions("Anything", " "))
    }

    func testAddressesThatOnlyDifferInSchemeWwwSlashOrFragmentAreTheSamePage() throws {
        let key = DaxPetBrowser.samePageKey(try XCTUnwrap(URL(string: "https://www.example.com/a/?q=1#top")))

        XCTAssertEqual(DaxPetBrowser.samePageKey(try XCTUnwrap(URL(string: "http://example.com/a?q=1"))), key)
        XCTAssertNotEqual(DaxPetBrowser.samePageKey(try XCTUnwrap(URL(string: "https://example.com/a?q=2"))), key)
    }

    func testTheLatestVisitToAPageIsFound() throws {
        let visits = [
            visit("https://a.example/page", title: "Page", at: 100),
            visit("https://a.example/page/", title: "Page", at: 300),
            visit("https://b.example/", title: "Other", at: 500)
        ]

        let found = DaxPetBrowser.lastVisit(to: try XCTUnwrap(URL(string: "https://a.example/page")), in: visits)

        XCTAssertEqual(found?.date, Date(timeIntervalSince1970: 300))
        XCTAssertNil(DaxPetBrowser.lastVisit(to: try XCTUnwrap(URL(string: "https://c.example/")), in: visits))
    }

    private func visit(_ url: String, title: String, at seconds: TimeInterval) -> Visit {
        let date = Date(timeIntervalSince1970: seconds)
        let entry = HistoryEntry(identifier: UUID(), url: URL(string: url)!, title: title, failedToLoad: false,
                                 numberOfTotalVisits: 1, lastVisit: date, visits: [], numberOfTrackersBlocked: 0,
                                 blockedTrackingEntities: [], trackersFound: false)
        retainedEntries.append(entry)
        return Visit(date: date, historyEntry: entry)
    }
}
