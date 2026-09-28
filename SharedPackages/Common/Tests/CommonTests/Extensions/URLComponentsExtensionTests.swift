//
//  URLComponentsExtensionTests.swift
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

import Common
import XCTest

final class URLComponentsExtensionTests: XCTestCase {

    private let tld = TLD()
    private let portSuffix = ":1234"
    private let domain = "https://www.duckduckgo.com"
    private let etldPlus1 = "duckduckgo.com"

    func testWhenGetETLDplus1WithPort_ThenPortIsReturnedWithResult() throws {
        // Given
        let domainAndPort = domain + portSuffix
        var sut = URLComponents(string: domainAndPort)

        // When
        let result = sut?.eTLDplus1WithPort(tld: tld)

        // Then
        XCTAssertTrue(result!.hasSuffix(portSuffix))
    }

    func testWhenGetETLDplus1WithOutPort_ThenETLDPlus1IsReturned() throws {
        // Given
        var sut = URLComponents(string: domain)

        // When
        let result = sut?.eTLDplus1WithPort(tld: tld)

        // Then
        XCTAssertEqual(result!, etldPlus1)
    }

    func testAddingSubdomainFromSourceURLComponents() throws {
        // Given
        var sut = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/subscriptions"))
        let sourceURLComponents = try XCTUnwrap(URLComponents(string: "https://subdomain.duck.co:1234/path?origin=test#fragment"))

        // When
        sut.addingSubdomain(from: sourceURLComponents, tld: tld)

        // Then
        XCTAssertEqual(sut.url?.absoluteString, "https://subdomain.duckduckgo.com/subscriptions")
    }

    func testAddingPortFromSourceURLComponents() throws {
        // Given
        var sut = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/subscriptions"))
        let sourceURLComponents = try XCTUnwrap(URLComponents(string: "https://subdomain.duck.co:1234/path?origin=test#fragment"))

        // When
        sut.addingPort(from: sourceURLComponents)

        // Then
        XCTAssertEqual(sut.url?.absoluteString, "https://www.duckduckgo.com:1234/subscriptions")
    }

    func testAddingQueryItemsFromSourceURLComponents() throws {
        // Given
        var sut = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/subscriptions"))
        let sourceURLComponents = try XCTUnwrap(URLComponents(string: "https://subdomain.duck.co:1234/path?origin=test#fragment"))

        // When
        sut.addingQueryItems(from: sourceURLComponents)

        // Then
        XCTAssertEqual(sut.url?.absoluteString, "https://www.duckduckgo.com/subscriptions?origin=test")
    }

    func testAddingFragmentFromSourceURLComponents() throws {
        // Given
        var sut = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/subscriptions"))
        let sourceURLComponents = try XCTUnwrap(URLComponents(string: "https://subdomain.duck.co:1234/path?origin=test#fragment"))

        // When
        sut.addingFragment(from: sourceURLComponents)

        // Then
        XCTAssertEqual(sut.url?.absoluteString, "https://www.duckduckgo.com/subscriptions#fragment")
    }

    func testAddingSubdomainPortQueryItemsAndFragmentFromSourceURLComponents() throws {
        // Given
        var sut = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/subscriptions"))
        let sourceURLComponents = try XCTUnwrap(URLComponents(string: "https://subdomain.duck.co:1234/path?origin=test#fragment"))

        // When
        sut.addingSubdomain(from: sourceURLComponents, tld: tld)
        sut.addingPort(from: sourceURLComponents)
        sut.addingQueryItems(from: sourceURLComponents)
        sut.addingFragment(from: sourceURLComponents)

        // Then
        XCTAssertEqual(sut.url?.absoluteString, "https://subdomain.duckduckgo.com:1234/subscriptions?origin=test#fragment")
    }

    func testWhenUsingPlainSourceURLOriginalIsUnchanged() throws {
        // Given
        var sut = try XCTUnwrap(URLComponents(string: "https://www.duckduckgo.com/subscriptions"))
        let sourceURLComponents = try XCTUnwrap(URLComponents(string: "https://duck.co/pro"))

        // When
        sut.addingSubdomain(from: sourceURLComponents, tld: tld)
        sut.addingPort(from: sourceURLComponents)
        sut.addingQueryItems(from: sourceURLComponents)
        sut.addingFragment(from: sourceURLComponents)

        // Then
        XCTAssertEqual(sut.url?.absoluteString, "https://www.duckduckgo.com/subscriptions")
    }

}
