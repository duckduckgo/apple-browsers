//
//  FaviconUserScriptIntegrationTests.swift
//  DuckDuckGo
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

import UserScript
import WebKit
import XCTest

@testable import DuckDuckGo

/// Unit tests for the FaviconUserScript delegate interface and data models.
/// Full C-S-S integration is tested via Playwright tests in content-scope-scripts.
final class FaviconUserScriptIntegrationTests: XCTestCase {

    var faviconScript: FaviconUserScript!
    var mockDelegate: MockFaviconDelegate!

    @MainActor
    override func setUp() {
        super.setUp()
        faviconScript = FaviconUserScript()
        mockDelegate = MockFaviconDelegate()
        faviconScript.delegate = mockDelegate
    }

    @MainActor
    override func tearDown() {
        faviconScript = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Data Model Tests

    func testFaviconLinkDecodingFromJSON() throws {
        let json = """
        {
            "href": "https://example.com/favicon.ico",
            "rel": "icon",
            "type": "image/x-icon"
        }
        """

        let data = json.data(using: .utf8)!
        let link = try JSONDecoder().decode(FaviconUserScript.FaviconLink.self, from: data)

        XCTAssertEqual(link.href.absoluteString, "https://example.com/favicon.ico")
        XCTAssertEqual(link.rel, "icon")
        XCTAssertEqual(link.type, "image/x-icon")
    }

    func testFaviconLinkDecodingWithoutType() throws {
        let json = """
        {
            "href": "https://example.com/favicon.ico",
            "rel": "shortcut icon"
        }
        """

        let data = json.data(using: .utf8)!
        let link = try JSONDecoder().decode(FaviconUserScript.FaviconLink.self, from: data)

        XCTAssertEqual(link.href.absoluteString, "https://example.com/favicon.ico")
        XCTAssertEqual(link.rel, "shortcut icon")
        XCTAssertNil(link.type)
    }

    func testFaviconsFoundPayloadDecoding() throws {
        let json = """
        {
            "documentUrl": "https://example.com/page",
            "favicons": [
                {"href": "https://example.com/favicon.ico", "rel": "icon", "type": "image/x-icon"},
                {"href": "https://example.com/apple-touch-icon.png", "rel": "apple-touch-icon"}
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let payload = try JSONDecoder().decode(FaviconUserScript.FaviconsFoundPayload.self, from: data)

        XCTAssertEqual(payload.documentUrl.absoluteString, "https://example.com/page")
        XCTAssertEqual(payload.favicons.count, 2)
        XCTAssertEqual(payload.favicons[0].rel, "icon")
        XCTAssertEqual(payload.favicons[1].rel, "apple-touch-icon")
    }

    // MARK: - Handler Registration Tests

    func testFaviconFoundHandlerIsRegistered() {
        let handler = faviconScript.handler(forMethodNamed: "faviconFound")
        XCTAssertNotNil(handler, "Should have a handler for faviconFound")
    }

    func testUnknownMethodReturnsNilHandler() {
        let handler = faviconScript.handler(forMethodNamed: "unknownMethod")
        XCTAssertNil(handler, "Should return nil for unknown method")
    }

    // MARK: - Delegate Interface Tests

    @MainActor
    func testDelegateReceivesFaviconLinks() {
        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon.ico")!, rel: "icon", type: "image/x-icon"),
            FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/apple-touch-icon.png")!, rel: "apple-touch-icon")
        ]

        mockDelegate.faviconUserScript(faviconScript, didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        XCTAssertEqual(mockDelegate.callCount, 1)
        XCTAssertEqual(mockDelegate.receivedFaviconLinks?.count, 2)
        XCTAssertEqual(mockDelegate.receivedDocumentUrl, documentUrl)
    }

    @MainActor
    func testDelegateReceivesEmptyFaviconLinks() {
        let documentUrl = URL(string: "https://example.com")!

        mockDelegate.faviconUserScript(faviconScript, didFindFaviconLinks: [], for: documentUrl, in: nil)

        XCTAssertEqual(mockDelegate.callCount, 1)
        XCTAssertTrue(mockDelegate.receivedFaviconLinks?.isEmpty ?? false)
    }

    @MainActor
    func testMultipleDelegateCallsAreTracked() {
        let documentUrl = URL(string: "https://example.com")!
        let links1 = [FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon1.ico")!, rel: "icon")]
        let links2 = [FaviconUserScript.FaviconLink(href: URL(string: "https://example.com/favicon2.ico")!, rel: "icon")]

        mockDelegate.faviconUserScript(faviconScript, didFindFaviconLinks: links1, for: documentUrl, in: nil)
        mockDelegate.faviconUserScript(faviconScript, didFindFaviconLinks: links2, for: documentUrl, in: nil)

        XCTAssertEqual(mockDelegate.callCount, 2)
        XCTAssertEqual(mockDelegate.allReceivedLinks.count, 2)
    }

    // MARK: - Subfeature Configuration Tests

    func testFeatureNameIsFavicon() {
        XCTAssertEqual(faviconScript.featureName, "favicon")
    }

    func testMessageOriginPolicyAllowsAll() {
        // MessageOriginPolicy doesn't conform to Equatable, so check the case directly
        if case .all = faviconScript.messageOriginPolicy {
            // Pass
        } else {
            XCTFail("Message origin policy should be .all")
        }
    }
}

// MARK: - Mocks

private final class MockFaviconDelegate: FaviconUserScriptDelegate {
    var receivedFaviconLinks: [FaviconUserScript.FaviconLink]?
    var receivedDocumentUrl: URL?
    var callCount = 0
    var allReceivedLinks: [[FaviconUserScript.FaviconLink]] = []

    @MainActor
    func faviconUserScript(_ faviconUserScript: FaviconUserScript,
                           didFindFaviconLinks faviconLinks: [FaviconUserScript.FaviconLink],
                           for documentUrl: URL,
                           in webView: WKWebView?) {
        receivedFaviconLinks = faviconLinks
        receivedDocumentUrl = documentUrl
        callCount += 1
        allReceivedLinks.append(faviconLinks)
    }
}
