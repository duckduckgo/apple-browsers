//
//  AutocompleteSuggestionsPixelsTests.swift
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

import XCTest
import Core
import Suggestions
@testable import DuckDuckGo

final class AutocompleteSuggestionsPixelsTests: XCTestCase {

    private var pixels: AutocompleteSuggestionsPixels!

    override func setUp() {
        super.setUp()
        PixelFiringMock.tearDown()
        pixels = AutocompleteSuggestionsPixels(pixelFiring: PixelFiringMock.self,
                                               dailyPixelFiring: PixelFiringMock.self)
    }

    override func tearDown() {
        PixelFiringMock.tearDown()
        pixels = nil
        super.tearDown()
    }

    private var firedNames: [String] { PixelFiringMock.allPixelsFired.compactMap { $0.pixelName } }

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: - Display

    func testDisplayFiresOnePixelPerLocalCategoryPresent() {
        pixels.fireDisplayPixels(for: [
            .bookmark(title: "b", url: url("https://a.com"), isFavorite: false, score: 0),
            .bookmark(title: "fav", url: url("https://b.com"), isFavorite: true, score: 0),
            .historyEntry(title: "h", url: url("https://c.com"), score: 0),
            .openTab(title: "t", url: url("https://d.com"), tabId: nil, score: 0)
        ])

        XCTAssertEqual(Set(firedNames), [
            Pixel.Event.autocompleteDisplayedLocalBookmark.name,
            Pixel.Event.autocompleteDisplayedLocalFavorite.name,
            Pixel.Event.autocompleteDisplayedLocalHistory.name,
            Pixel.Event.autocompleteDisplayedOpenedTab.name
        ])
    }

    func testDisplayDedupesRepeatedCategories() {
        pixels.fireDisplayPixels(for: [
            .bookmark(title: "b1", url: url("https://a.com"), isFavorite: false, score: 0),
            .bookmark(title: "b2", url: url("https://b.com"), isFavorite: false, score: 0),
            .historyEntry(title: "h1", url: url("https://c.com"), score: 0),
            .historyEntry(title: "h2", url: url("https://d.com"), score: 0)
        ])

        XCTAssertEqual(firedNames.sorted(), [
            Pixel.Event.autocompleteDisplayedLocalBookmark.name,
            Pixel.Event.autocompleteDisplayedLocalHistory.name
        ].sorted())
    }

    func testDisplayIgnoresPhraseAndWebsite() {
        pixels.fireDisplayPixels(for: [
            .phrase(phrase: "q"),
            .website(url: url("https://a.com"))
        ])
        XCTAssertTrue(firedNames.isEmpty)
    }

    func testDisplayEmptyFiresNothing() {
        pixels.fireDisplayPixels(for: [])
        XCTAssertTrue(firedNames.isEmpty)
    }

    // MARK: - Click

    func testClickBookmark() {
        pixels.fireClickPixel(for: .bookmark(title: "b", url: url("https://a.com"), isFavorite: false, score: 0))
        XCTAssertEqual(firedNames, [Pixel.Event.autocompleteClickBookmark.name])
    }

    func testClickFavorite() {
        pixels.fireClickPixel(for: .bookmark(title: "b", url: url("https://a.com"), isFavorite: true, score: 0))
        XCTAssertEqual(firedNames, [Pixel.Event.autocompleteClickFavorite.name])
    }

    func testClickSearchHistory() {
        pixels.fireClickPixel(for: .historyEntry(title: "h", url: url("https://duckduckgo.com/?q=cats"), score: 0))
        XCTAssertEqual(firedNames, [Pixel.Event.autocompleteClickSearchHistory.name])
    }

    func testClickSiteHistory() {
        pixels.fireClickPixel(for: .historyEntry(title: "h", url: url("https://example.com/page"), score: 0))
        XCTAssertEqual(firedNames, [Pixel.Event.autocompleteClickSiteHistory.name])
    }

    func testClickPhrase() {
        pixels.fireClickPixel(for: .phrase(phrase: "q"))
        XCTAssertEqual(firedNames, [Pixel.Event.autocompleteClickPhrase.name])
    }

    func testClickWebsite() {
        pixels.fireClickPixel(for: .website(url: url("https://a.com")))
        XCTAssertEqual(firedNames, [Pixel.Event.autocompleteClickWebsite.name])
    }

    func testClickSwitchToTab() {
        pixels.fireClickPixel(for: .openTab(title: "t", url: url("https://a.com"), tabId: "1", score: 0))
        XCTAssertEqual(firedNames, [Pixel.Event.autocompleteClickOpenTab.name])
    }

    func testClickAskAIChatIsHandledSeparately() {
        pixels.fireClickPixel(for: .askAIChat(value: "q"))
        XCTAssertTrue(firedNames.isEmpty)
    }

    // MARK: - Ask AI Chat (daily)

    func testAskAIChatExperimentalDailyPixel() {
        pixels.fireAskAIChatClickPixel(isExperimentalExperience: true, additionalParameters: [:])
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName,
                       Pixel.Event.autocompleteAskAIChatExperimentalExperience.name)
    }

    func testAskAIChatLegacyDailyPixel() {
        pixels.fireAskAIChatClickPixel(isExperimentalExperience: false, additionalParameters: [:])
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName,
                       Pixel.Event.autocompleteAskAIChatLegacyExperience.name)
    }
}
