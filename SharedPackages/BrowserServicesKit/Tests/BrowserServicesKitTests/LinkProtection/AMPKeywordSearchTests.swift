//
//  AMPKeywordSearchTests.swift
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
@testable import BrowserServicesKit

final class AMPKeywordSearchTests: XCTestCase {

    private let keywords = ["amp=", "=amp", "&amp", "amp&", "/amp", "amp/", ".amp", "amp.", "%amp", "amp%", "_amp", "amp_", "?amp"]

    private func contains(_ url: String) -> Bool {
        AMPCanonicalExtractor.urlString(url, containsAnyOf: keywords)
    }

    func testWhenKeywordIsInPathOrQueryThenItIsFound() {
        XCTAssertTrue(contains("https://example.com/amp/article"))
        XCTAssertTrue(contains("https://example.com/article.amp"))
        XCTAssertTrue(contains("https://example.com/article?amp=1"))
        XCTAssertTrue(contains("https://example.com/article?a=1&amp"))
        XCTAssertTrue(contains("https://example.com/article?a=%amp"))
    }

    func testWhenNoKeywordThenNothingIsFound() {
        XCTAssertFalse(contains("https://example.com/article?a=1&b=2"))
        XCTAssertFalse(contains("https://example.com/"))
        XCTAssertFalse(contains(""))
    }

    func testWhenKeywordIsEmptyThenItNeverMatches() {
        XCTAssertFalse(AMPCanonicalExtractor.urlString("https://example.com/article", containsAnyOf: [""]))
        XCTAssertTrue(AMPCanonicalExtractor.urlString("https://example.com/amp/article", containsAnyOf: ["", "/amp"]))
    }

    func testWhenKeywordIsOnlyInFragmentThenItIsIgnored() {
        XCTAssertFalse(contains("https://example.com/article#/amp/"))
        XCTAssertFalse(contains("https://example.com/article#?amp=1"))
        XCTAssertFalse(contains("https://example.com/article#"))
        XCTAssertTrue(contains("https://example.com/amp/article#fragment"))
    }

    func testWhenHashIsEncodedThenItDoesNotEndTheSearch() {
        XCTAssertTrue(contains("https://example.com/article?a=%23&amp=1"))
        XCTAssertFalse(contains("https://example.com/article?a=%23#frag&amp"))
    }

    func testWhenKeywordIsAtTheEndOfALongURLThenItIsFound() {
        let filler = String(repeating: "b=1&", count: 20_000)
        XCTAssertTrue(contains("https://example.com/?" + filler + "?amp"))
        XCTAssertTrue(contains("https://example.com/?amp=1&" + filler))
        XCTAssertFalse(contains("https://example.com/?" + filler))
    }

    func testWhenURLIsMultipleMegabytesThenSearchIsFast() throws {
        let filler = String(repeating: "a=1&utm_source=x&", count: 1_000_000)
        let url = try XCTUnwrap(NSURL(string: "https://example.com/?" + filler) as URL?)

        let start = Date()
        let found = AMPCanonicalExtractor.urlString(url.absoluteString, containsAnyOf: keywords)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(found)
        XCTAssertLessThan(elapsed, 2, "Searching a 17 MB URL took \(elapsed)s")
    }

}
