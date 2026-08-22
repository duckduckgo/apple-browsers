//
//  SearchURLBuilderTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
@testable import AppRouting

final class SearchURLBuilderTests: XCTestCase {

    private let searchBaseURL = URL(string: "https://duckduckgo.com")!
    private var atbWithVariant: String?

    override func setUp() {
        super.setUp()
        atbWithVariant = nil
    }

    func testWhenSearchBaseURLIsNotProvidedThenProductionURLIsUsed() {
        let url = SearchURLBuilder(isPad: false).makeSearchURL(query: "query", forceSearchQuery: true)

        XCTAssertEqual(url.absoluteString, "https://duckduckgo.com/?q=query&t=ddg_ios")
    }

    func testWhenMobileStatsParamsAreAppliedThenTheyReturnAnUpdatedUrl() {
        atbWithVariant = "x"
        let actual = makeSearchURLBuilder()
            .applyingStatsParams(to: URL(string: "http://duckduckgo.com?atb=wrong&t=wrong")!)
        XCTAssertEqual(actual.getParameter(named: "atb"), "x")
        XCTAssertEqual(actual.getParameter(named: "t"), "ddg_ios")
    }

    func testWhenAtbMatchesThenHasMobileStatsParamsIsTrue() {
        atbWithVariant = "x"
        let result = makeSearchURLBuilder()
            .hasCorrectMobileStatsParams(url: URL(string: "http://duckduckgo.com?atb=x&t=ddg_ios")!)
        XCTAssertTrue(result)
    }

    func testWhenAtbIsMismatchedThenHasMobileStatsParamsIsFalse() {
        atbWithVariant = "y"
        let result = makeSearchURLBuilder()
            .hasCorrectMobileStatsParams(url: URL(string: "http://duckduckgo.com?atb=x&t=ddg_ios")!)
        XCTAssertFalse(result)
    }

    func testWhenAtbIsMissingThenHasMobileStatsParamsIsFalse() {
        atbWithVariant = "x"
        let result = makeSearchURLBuilder()
            .hasCorrectMobileStatsParams(url: URL(string: "http://duckduckgo.com?t=ddg_ios")!)
        XCTAssertFalse(result)
    }

    func testWhenSourceIsMismatchedThenHasMobileStatsParamsIsFalse() {
        atbWithVariant = "x"
        let result = makeSearchURLBuilder()
            .hasCorrectMobileStatsParams(url: URL(string: "http://duckduckgo.com?atb=x&t=ddg_desktop")!)
        XCTAssertFalse(result)
    }

    func testWhenSourceIsMissingThenHasMobileStatsParamsIsFalse() {
        atbWithVariant = "x"
        let result = makeSearchURLBuilder()
            .hasCorrectMobileStatsParams(url: URL(string: "http://duckduckgo.com?atb=y")!)
        XCTAssertFalse(result)
    }

    func testWhenSearchURLIsBuiltThenQueryEncodingAndSourceArePreserved() {
        let url = makeSearchURLBuilder().makeSearchURL(query: "a+b / c&d", forceSearchQuery: true)

        XCTAssertEqual(url.absoluteString, "https://duckduckgo.com/?q=a%2Bb+%2F+c%26d&t=ddg_ios")
    }

    func testSearchUrlCreatesSearchUrlWhenFloatingPointNumberIsPassed() {
        let url = makeSearchURLBuilder().makeSearchURL(query: "1.4")
        XCTAssertEqual(url.getParameter(named: "q"), "1.4")
    }

    func testSearchUrlCreatesSearchUrlWhenFloatingPointNumbersDivisionIsPassed() {
        let url = makeSearchURLBuilder().makeSearchURL(query: "1.4/3.4")
        XCTAssertEqual(url.getParameter(named: "q"), "1.4/3.4")

        let url2 = makeSearchURLBuilder().makeSearchURL(query: "4/3.4")
        XCTAssertEqual(url2.getParameter(named: "q"), "4/3.4")
    }

    func testSearchUrlCreatesWebUrlWhenIPv4WithFourOctetsIsPassed() {
        let url = makeSearchURLBuilder().makeSearchURL(query: "1.0.0.4/3.4")
        XCTAssertEqual(url.absoluteString, "http://1.0.0.4/3.4")
    }

    func testWhenDomainLikeInputIsUsedThenForceSearchControlsTheResult() {
        let builder = makeSearchURLBuilder()
        let navigationURL = builder.makeSearchURL(query: "example.com")
        atbWithVariant = "v123-4ru"
        let searchURL = builder.makeSearchURL(query: "example.com", forceSearchQuery: true)

        XCTAssertEqual(navigationURL.absoluteString, "http://example.com")
        XCTAssertEqual(searchURL.absoluteString, "https://duckduckgo.com/?q=example.com&t=ddg_ios&atb=v123-4ru")
    }

    func testSearchUrlCreatesUrlWithSourceParamForiPad() {
        let url = makeSearchURLBuilder(isPad: true).makeSearchURL(query: "query", forceSearchQuery: true)
        XCTAssertEqual(url.getParameter(named: "t"), "ddg_ios_tablet")
    }

    func testWhenExistingQueryUsesVerticalThenItIsAppliedToNewOne() {
        let contextURL = URL(string: "https://duckduckgo.com/?q=query&iar=images&ko=-1&ia=images")!
        let url = makeSearchURLBuilder()
            .makeSearchURL(query: "query", queryContext: contextURL)

        XCTAssertEqual(url.getParameter(named: "t"), "ddg_ios")
        XCTAssertEqual(url.getParameter(named: "iar"), "images")
    }

    func testWhenExistingQueryUsesVerticalWithMapsThenTheseAreIgnored() {
        let contextURL = URL(string: "https://duckduckgo.com/?q=query&iar=images&ko=-1&ia=images&iaxm=maps")!
        let url = makeSearchURLBuilder()
            .makeSearchURL(query: "query", queryContext: contextURL)

        XCTAssertEqual(url.getParameter(named: "t"), "ddg_ios")
        XCTAssertNil(url.getParameter(named: "ia"))
        XCTAssertNil(url.getParameter(named: "iaxm"))
        XCTAssertNil(url.getParameter(named: "iar"))
    }

    func testWhenExistingQueryHasNoVerticalThenItIsAbsentInNewOne() {
        let contextURL = URL(string: "https://example.com")!
        let url = makeSearchURLBuilder()
            .makeSearchURL(query: "query", queryContext: contextURL)

        XCTAssertEqual(url.getParameter(named: "t"), "ddg_ios")
        XCTAssertNil(url.getParameter(named: "iar"))
    }

    private func makeSearchURLBuilder(isPad: Bool = false) -> SearchURLBuilder {
        SearchURLBuilder(searchBaseURL: searchBaseURL, isPad: isPad) {
            self.atbWithVariant
        }
    }
}
