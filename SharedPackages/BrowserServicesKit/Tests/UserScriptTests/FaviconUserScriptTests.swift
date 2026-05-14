//
//  FaviconUserScriptTests.swift
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

import Foundation
import WebKit
import XCTest

@testable import UserScript

final class FaviconUserScriptTests: XCTestCase {

    // MARK: - Handler Registration Tests

    func testHandlerReturnsFunctionForFaviconFoundMethod() {
        let script = FaviconUserScript()
        let handler = script.handler(forMethodNamed: "faviconFound")

        XCTAssertNotNil(handler, "Should return a handler for faviconFound method")
    }

    func testHandlerReturnsNilForUnknownMethod() {
        let script = FaviconUserScript()
        let handler = script.handler(forMethodNamed: "unknownMethod")

        XCTAssertNil(handler, "Should return nil for unknown method names")
    }

    func testHandlerReturnsNilForEmptyMethodName() {
        let script = FaviconUserScript()
        let handler = script.handler(forMethodNamed: "")

        XCTAssertNil(handler, "Should return nil for empty method name")
    }

    // MARK: - Data Model Tests

    func testFaviconLinkEquatable() {
        let url = URL(string: "https://example.com/favicon.ico")!
        let link1 = FaviconUserScript.FaviconLink(href: url, rel: "icon", type: "image/x-icon")
        let link2 = FaviconUserScript.FaviconLink(href: url, rel: "icon", type: "image/x-icon")
        let link3 = FaviconUserScript.FaviconLink(href: url, rel: "shortcut icon", type: "image/x-icon")

        XCTAssertEqual(link1, link2, "Same properties should be equal")
        XCTAssertNotEqual(link1, link3, "Different rel should not be equal")
    }

    func testFaviconLinkWithNilType() {
        let url = URL(string: "https://example.com/favicon.ico")!
        let link = FaviconUserScript.FaviconLink(href: url, rel: "icon")

        XCTAssertNil(link.type, "Type should be nil when not provided")
    }

    func testFaviconLinkCodable() throws {
        let url = URL(string: "https://example.com/favicon.ico")!
        let link = FaviconUserScript.FaviconLink(href: url, rel: "icon", type: "image/x-icon")

        let encoder = JSONEncoder()
        let data = try encoder.encode(link)

        let decoder = JSONDecoder()
        let decodedLink = try decoder.decode(FaviconUserScript.FaviconLink.self, from: data)

        XCTAssertEqual(link, decodedLink, "Should round-trip through JSON encoding/decoding")
    }

    func testFaviconsFoundPayloadCodable() throws {
        let url = URL(string: "https://example.com/favicon.ico")!
        let documentUrl = URL(string: "https://example.com")!
        let link = FaviconUserScript.FaviconLink(href: url, rel: "icon", type: "image/x-icon")
        let payload = FaviconUserScript.FaviconsFoundPayload(documentUrl: documentUrl, favicons: [link])

        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        let decodedPayload = try decoder.decode(FaviconUserScript.FaviconsFoundPayload.self, from: data)

        XCTAssertEqual(payload, decodedPayload, "Should round-trip through JSON encoding/decoding")
    }

    func testFaviconsFoundPayloadWithMultipleFavicons() throws {
        let documentUrl = URL(string: "https://example.com")!
        let icons = [
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.ico")!, rel: "icon", type: "image/x-icon"),
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.svg")!, rel: "icon", type: "image/svg+xml"),
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/apple-touch-icon.png")!, rel: "apple-touch-icon")
        ]
        let payload = FaviconUserScript.FaviconsFoundPayload(documentUrl: documentUrl, favicons: icons)

        XCTAssertEqual(payload.favicons.count, 3, "Should preserve all favicons")
        XCTAssertEqual(payload.documentUrl, documentUrl, "Should preserve document URL")
    }

    func testFaviconsFoundPayloadWithEmptyFavicons() {
        let documentUrl = URL(string: "https://example.com")!
        let payload = FaviconUserScript.FaviconsFoundPayload(documentUrl: documentUrl, favicons: [])

        XCTAssertTrue(payload.favicons.isEmpty, "Should allow empty favicons array")
        XCTAssertEqual(payload.documentUrl, documentUrl, "Should preserve document URL")
    }

    // MARK: - Subfeature Configuration Tests

    func testFeatureNameIsFavicon() {
        let script = FaviconUserScript()

        XCTAssertEqual(script.featureName, "favicon", "Feature name should be 'favicon'")
    }

    func testMessageOriginPolicyIsAll() {
        let script = FaviconUserScript()

        // MessageOriginPolicy doesn't conform to Equatable, so check the case directly
        if case .all = script.messageOriginPolicy {
            // Pass
        } else {
            XCTFail("Message origin policy should be .all")
        }
    }

    // MARK: - Delegate Tests

    func testDelegateIsWeaklyReferenced() {
        let script = FaviconUserScript()
        var delegate: MockFaviconUserScriptDelegate? = MockFaviconUserScriptDelegate()

        script.delegate = delegate
        XCTAssertNotNil(script.delegate, "Delegate should be set")

        delegate = nil
        XCTAssertNil(script.delegate, "Delegate should be nil after deallocation (weak reference)")
    }

    func testBrokerIsWeaklyReferenced() {
        let script = FaviconUserScript()
        var broker: UserScriptMessageBroker? = UserScriptMessageBroker(context: "test")

        script.broker = broker
        XCTAssertNotNil(script.broker, "Broker should be set")

        broker = nil
        XCTAssertNil(script.broker, "Broker should be nil after deallocation (weak reference)")
    }
}

// MARK: - Mocks

private final class MockFaviconUserScriptDelegate: FaviconUserScriptDelegate {
    var receivedFaviconLinks: [FaviconUserScript.FaviconLink]?
    var receivedDocumentUrl: URL?
    var callCount = 0

    @MainActor
    func faviconUserScript(_ faviconUserScript: FaviconUserScript,
                           didFindFaviconLinks faviconLinks: [FaviconUserScript.FaviconLink],
                           for documentUrl: URL,
                           in webView: WKWebView?) {
        receivedFaviconLinks = faviconLinks
        receivedDocumentUrl = documentUrl
        callCount += 1
    }
}
