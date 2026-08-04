//
//  URLInputClassifierTests.swift
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

class URLInputClassifierTests: XCTestCase {

    func testWhenURLHasLongTLDItStillIsConsideredValid() {
        XCTAssertTrue(URLInputClassifier.isWebUrl("https://blah.accountants"))
    }

    func testWhenGivenLongWellFormedUrlThenIsWebUrlIsTrue() {
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://www.veganchic.com/products/Camo-High-Top-Sneaker-by-The-Critical-Slide-Societ+80758-0180.html"))
    }

    func testWhenHostIsValidThenIsWebUrlIsTrue() {
        XCTAssertTrue(URLInputClassifier.isWebUrl("test.com"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("121.33.2.11"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("localhost"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("myhost.local"))
    }

    func testWhenHostIsInvalidThenIsWebUrlIsFalse() {
        XCTAssertFalse(URLInputClassifier.isWebUrl("t est.com"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("test!com.com"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("121.33.33."))
        XCTAssertFalse(URLInputClassifier.isWebUrl("localhostt"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("localserver"))
    }

    func testWhenSchemeIsValidThenIsWebUrlIsTrue() {
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://test.com"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://121.33.2.11"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://localhost"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://localserver"))
    }

    func testWhenSchemeIsInvalidThenIsWebUrlIsFalse() {
        XCTAssertFalse(URLInputClassifier.isWebUrl("asdas://test.com"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("asdas://121.33.2.11"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("asdas://localhost"))
    }

    func testWhenTextIsIncompleteSchemeThenIsWebUrlIsFalse() {
        XCTAssertFalse(URLInputClassifier.isWebUrl("http"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("http:"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("http:/"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("https"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("https:"))
        XCTAssertFalse(URLInputClassifier.isWebUrl("https:/"))
    }

    func testWhenPathIsValidThenIsWebUrlIsTrue() {
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://test.com/path"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://121.33.2.11/path"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://localhost/path"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("test.com/path"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("121.33.2.11/path"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("localhost/path"))
    }

    func testWhenParamsAreValidThenIsWebUrlIsTrue() {
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://test.com?s=dafas&d=342"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://121.33.2.11?s=dafas&d=342"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("http://localhost?s=dafas&d=342"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("test.com?s=dafas&d=342"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("121.33.2.11?s=dafas&d=342"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("localhost?s=dafas&d=342"))
        XCTAssertTrue(URLInputClassifier.isWebUrl("https://m.facebook.com/?refsrc=https%3A%2F%2Fwww.facebook.com%2F&_rdr"))
    }

    func testWhenGivenSimpleStringThenIsWebUrlIsFalse() {
        XCTAssertFalse(URLInputClassifier.isWebUrl("randomtext"))
    }

    func testWhenGivenStringWithDotPrefixThenIsWebUrlIsFalse() {
        XCTAssertFalse(URLInputClassifier.isWebUrl(".randomtext"))
    }

    func testWhenGivenStringWithDotSuffixThenIsWebUrlIsFalse() {
        XCTAssertFalse(URLInputClassifier.isWebUrl("randomtext."))
    }

    func testWhenGivenNumberThenIsWebUrlIsFalse() {
        XCTAssertFalse(URLInputClassifier.isWebUrl("33"))
    }

    func testWhenWebUrlCalledWithValidURLThenSameUrlIsReturned() {
        let input = "http://test.com"
        let result = URLInputClassifier.webUrl(from: input)
        XCTAssertNotNil(result)
        XCTAssertEqual(input, result?.absoluteString)
    }

    func testWhenWebUrlCalledWithInvalidURLThenNilIsReturned() {
        let result = URLInputClassifier.webUrl(from: "http://test .com")
        XCTAssertNil(result)
    }

    func testWhenWebUrlCalledWithoutSchemeThenSchemeIsAdded() {
        let result = URLInputClassifier.webUrl(from: "test.com")
        XCTAssertNotNil(result)
        XCTAssertEqual("http://test.com", result?.absoluteString)
    }

    func testWhenAddressBarInputHasWhitespaceThenIsValidAddressBarURLInputIsFalse() {
        XCTAssertFalse(URLInputClassifier.isValidAddressBarURLInput("https://example .com"))
        XCTAssertFalse(URLInputClassifier.isValidAddressBarURLInput("example com"))
    }

    func testWhenAddressBarInputIsValidURLThenIsValidAddressBarURLInputIsTrue() {
        XCTAssertTrue(URLInputClassifier.isValidAddressBarURLInput("https://example.com/path"))
        XCTAssertTrue(URLInputClassifier.isValidAddressBarURLInput("example.com"))
    }
}

extension URLInputClassifier {

    static func isWebUrl(_ text: String) -> Bool {
        webUrl(from: text) != nil
    }
}
