//
//  HTTPURLResponseCookiesTests.swift
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

final class HTTPURLResponseCookiesTests: XCTestCase {

    func getCookie(withName name: String, from cookies: [HTTPCookie]?) -> HTTPCookie? {
        return cookies?.compactMap({ cookie in
            if cookie.name == name {
                return cookie
            } else {
                return nil
            }
        }).last
    }

    func testCookiesRetrievesAllCookies() {
        let url = URL(string: "https://example.com")!
        let cookieHeader = "Set-Cookie"
        let cookieValue1 = "name1=value1; Path=/; HttpOnly"
        let cookieValue2 = "name2=value2; Path=/; Secure"
        let headers = [cookieHeader: "\(cookieValue1), \(cookieValue2)"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let cookies = response?.cookies
        XCTAssertEqual(cookies?.count, 2)

        let c0 = getCookie(withName: "name1", from: cookies)
        XCTAssertEqual(c0?.name, "name1")
        XCTAssertEqual(c0?.value, "value1")

        let c1 = getCookie(withName: "name2", from: cookies)
        XCTAssertEqual(c1?.name, "name2")
        XCTAssertEqual(c1?.value, "value2")
    }

    func testGetCookieWithNameReturnsCorrectCookie() {
        let url = URL(string: "https://example.com")!
        let cookieHeader = "Set-Cookie"
        let cookieValue1 = "name1=value1; Path=/; HttpOnly"
        let cookieValue2 = "name2=value2; Path=/; Secure"
        let headers = [cookieHeader: "\(cookieValue1), \(cookieValue2)"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let cookie = response?.getCookie(withName: "name2")
        XCTAssertNotNil(cookie)
        XCTAssertEqual(cookie?.name, "name2")
        XCTAssertEqual(cookie?.value, "value2")
    }

    func testGetCookieWithNameReturnsNilForNonExistentCookie() {
        let url = URL(string: "https://example.com")!
        let cookieHeader = "Set-Cookie"
        let cookieValue1 = "name1=value1; Path=/; HttpOnly"
        let headers = [cookieHeader: cookieValue1]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)

        let cookie = response?.getCookie(withName: "nonexistent")
        XCTAssertNil(cookie)
    }

    func testCookiesReturnsNilWhenNoCookieHeaderFields() {
        let url = URL(string: "https://example.com")!
        let headers: [String: String] = [:]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)
        XCTAssertTrue(response!.cookies!.isEmpty)
    }
}
