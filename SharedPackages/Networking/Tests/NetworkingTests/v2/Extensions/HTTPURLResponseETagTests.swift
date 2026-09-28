//
//  HTTPURLResponseETagTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

final class HTTPURLResponseETagTests: XCTestCase {

    func testEtagReturnsStrongEtag() {
        let url = URL(string: "https://example.com")!
        let headers = ["Etag": "\"12345\""]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let etag = response?.etag
        XCTAssertEqual(etag, "\"12345\"")
    }

    func testEtagReturnsWeakEtagWithoutPrefix() {
        let url = URL(string: "https://example.com")!
        let headers = ["Etag": "W/\"12345\""]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let etag = response?.etag
        XCTAssertEqual(etag, "\"12345\"")  // Weak prefix "W/" should be dropped
    }

    func testEtagRetainsWeakPrefixWhenDroppingWeakPrefixIsFalse() {
        let url = URL(string: "https://example.com")!
        let headers = ["Etag": "W/\"12345\""]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let etag = response?.etag(droppingWeakPrefix: false)
        XCTAssertEqual(etag, "W/\"12345\"")  // Weak prefix "W/" should be retained
    }

    func testEtagReturnsNilWhenNoEtagHeaderPresent() {
        let url = URL(string: "https://example.com")!
        let headers: [String: String] = [:]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let etag = response?.etag
        XCTAssertNil(etag)
    }

    func testEtagReturnsEmptyStringForEmptyEtagHeader() {
        let url = URL(string: "https://example.com")!
        let headers = ["Etag": ""]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let etag = response?.etag
        XCTAssertEqual(etag, "")
    }
}
