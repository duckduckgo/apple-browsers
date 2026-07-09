//
//  SafariRedirectHandlerTests.swift
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
import Common
import FoundationExtensions
import BrowserServicesKit
@testable import DuckDuckGo

final class SafariRedirectHandlerTests: XCTestCase {

    private var handler: SafariRedirectHandler!
    private var delegate: MockSafariRedirectHandlerDelegate!

    private let xSafariHTTPSURL = URL(string: "x-safari-https://example.com/page")!
    private let httpsURL = URL(string: "https://example.com/page")!
    private let regularURL = URL(string: "https://example.com/other")!

    override func setUp() {
        super.setUp()
        handler = SafariRedirectHandler(tld: TLD())
        delegate = MockSafariRedirectHandlerDelegate()
        handler.delegate = delegate
    }

    // MARK: - Non x-safari URLs

    func testHandleRedirectReturnsFalseForNonXSafariScheme() {
        XCTAssertFalse(handler.handleRedirect(to: regularURL))
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testHandleRedirectReturnsFalseForHTTPScheme() {
        let httpURL = URL(string: "http://example.com/page")!
        XCTAssertFalse(handler.handleRedirect(to: httpURL))
    }

    // MARK: - First redirect

    func testFirstHTTPSRedirectConvertsToHTTPSAndLoads() {
        XCTAssertTrue(handler.handleRedirect(to: xSafariHTTPSURL))

        XCTAssertEqual(delegate.loadedURLs.count, 1)
        XCTAssertEqual(delegate.loadedURLs.first?.scheme, "https")
        XCTAssertEqual(delegate.loadedURLs.first?.host, "example.com")
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    // MARK: - Loop handling

    func testFirstThreeRedirectsConvertToHTTPSAndLoad() {
        for _ in 0..<3 {
            XCTAssertTrue(handler.handleRedirect(to: xSafariHTTPSURL))
        }

        XCTAssertEqual(delegate.loadedURLs.count, 3)
        XCTAssertTrue(delegate.loadedURLs.allSatisfy { $0.scheme == "https" })
        XCTAssertTrue(delegate.loadedURLs.allSatisfy { $0.host == "example.com" })
        XCTAssertTrue(delegate.loopErrorURLs.isEmpty)
    }

    func testFourthRedirectRequestsLoopError() {
        for _ in 0..<3 {
            _ = handler.handleRedirect(to: xSafariHTTPSURL)
        }
        XCTAssertTrue(handler.handleRedirect(to: xSafariHTTPSURL))

        XCTAssertEqual(delegate.loadedURLs.count, 3)
        XCTAssertEqual(delegate.loopErrorURLs.count, 1)
        XCTAssertEqual(delegate.loopErrorURLs.first?.scheme, "x-safari-https")
        XCTAssertEqual(delegate.loopErrorURLs.first?.host, "example.com")
    }

    func testAdditionalRedirectsAfterMaximumAttemptsKeepRequestingLoopError() {
        for _ in 0..<3 {
            _ = handler.handleRedirect(to: xSafariHTTPSURL)
        }

        XCTAssertTrue(handler.handleRedirect(to: xSafariHTTPSURL))
        XCTAssertTrue(handler.handleRedirect(to: xSafariHTTPSURL))
        XCTAssertTrue(handler.handleRedirect(to: xSafariHTTPSURL))

        XCTAssertEqual(delegate.loadedURLs.count, 3)
        XCTAssertEqual(delegate.loopErrorURLs.count, 3)
    }

    // MARK: - Per-host scoping

    func testDifferentHostGetsFreshRetryBudget() {
        _ = handler.handleRedirect(to: xSafariHTTPSURL)

        let otherHostURL = URL(string: "x-safari-https://other.com/page")!
        _ = handler.handleRedirect(to: otherHostURL)

        XCTAssertEqual(delegate.loadedURLs.count, 2)
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: URL(string: "https://other.com/page")!))
    }

    func testSuppressedRedirectTrackedPerHost() {
        _ = handler.handleRedirect(to: xSafariHTTPSURL)

        let otherHostURL = URL(string: "x-safari-https://other.com/page")!
        _ = handler.handleRedirect(to: otherHostURL)

        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: URL(string: "https://other.com/page")!))
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: URL(string: "https://unrelated.com")!))
    }

    func testSubdomainRedirectMatchesParentDomain() {
        let subdomainURL = URL(string: "x-safari-https://redirect.example.com/page")!
        _ = handler.handleRedirect(to: subdomainURL)

        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        _ = handler.handleRedirect(to: xSafariHTTPSURL)
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))

        handler.reset()

        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testResetAfterMaximumAttemptsStartsFresh() {
        for _ in 0..<3 {
            _ = handler.handleRedirect(to: xSafariHTTPSURL)
        }
        _ = handler.handleRedirect(to: xSafariHTTPSURL)

        handler.reset()

        _ = handler.handleRedirect(to: xSafariHTTPSURL)
        XCTAssertEqual(delegate.loadedURLs.count, 4)
        XCTAssertEqual(delegate.loopErrorURLs.count, 1)
    }

    // MARK: - isAfterSuppressedXSafariRedirect

    func testIsAfterSuppressedXSafariRedirectPersistsAcrossMultipleRedirects() {
        _ = handler.handleRedirect(to: xSafariHTTPSURL)
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))

        _ = handler.handleRedirect(to: xSafariHTTPSURL)
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testIsAfterSuppressedXSafariRedirectFalseByDefault() {
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testIsAfterSuppressedXSafariRedirectFalseForDifferentHost() {
        _ = handler.handleRedirect(to: xSafariHTTPSURL)
        let differentHostURL = URL(string: "https://other.com/page")!
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: differentHostURL))
    }
}

// MARK: - Mock Delegate

private final class MockSafariRedirectHandlerDelegate: SafariRedirectHandlerDelegate {

    var loadedURLs: [URL] = []
    var loopErrorURLs: [URL] = []

    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestLoadURL url: URL) {
        loadedURLs.append(url)
    }

    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestShowSafariRedirectLoopErrorForURL url: URL) {
        loopErrorURLs.append(url)
    }
}
