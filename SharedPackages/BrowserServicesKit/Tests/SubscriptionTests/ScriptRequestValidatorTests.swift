//
//  ScriptRequestValidatorTests.swift
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
import WebKit
@testable import Subscription
import SubscriptionTestingUtilities

@MainActor
final class ScriptRequestValidatorTests: XCTestCase {

    var validator: DefaultScriptRequestValidator!
    var subscriptionManager: SubscriptionManagerMock!
    let validHost = "duckduckgo.com"
    let validBaseURL = URL(string: "https://duckduckgo.com/subscriptions")!

    override func setUp() {
        super.setUp()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultURL = validBaseURL
        validator = DefaultScriptRequestValidator(subscriptionManager: subscriptionManager)
    }

    override func tearDown() {
        validator = nil
        subscriptionManager = nil
        super.tearDown()
    }

    // MARK: - Valid Request Tests

    func testCanPageRequestToken_ValidMainFrameRequest_ReturnsTrue() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/welcome")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Valid main frame request from authorized path should be allowed")
    }

    func testCanPageRequestToken_BaseURLPath_ReturnsTrue() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Base URL path should be allowed")
    }

    func testCanPageRequestToken_AllValidPaths_ReturnTrue() async throws {
        // Given
        let validPaths = SubscriptionURL.allSubscriptionPaths()

        // When/Then
        for path in validPaths {
            let urlString = path.isEmpty ? "https://duckduckgo.com/subscriptions" : "https://duckduckgo.com/\(path)"
            let url = URL(string: urlString)!
            let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

            let result = await validator.canPageRequestToken(message)
            XCTAssertTrue(result, "Path '\(path)' should be allowed")
        }
    }

    // MARK: - Main Frame Tests

    func testCanPageRequestToken_NotMainFrame_ReturnsFalse() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/welcome")!
        let message = createMockMessage(url: url, isMainFrame: false, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertFalse(result, "Iframe requests should be rejected")
    }

    // MARK: - URL and Host Tests

    func testCanPageRequestToken_MissingURL_ReturnsFalse() async throws {
        // Given
        let message = createMockMessage(url: nil, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertFalse(result, "Requests without a URL should be rejected")
    }

    func testCanPageRequestToken_WrongHost_ReturnsFalse() async throws {
        // Given
        let url = URL(string: "https://evil.com/subscriptions/welcome")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: "evil.com")

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertFalse(result, "Requests from wrong host should be rejected")
    }

    // MARK: - Scheme Validation Tests

    func testCanPageRequestToken_HTTPScheme_ReturnsFalse() async throws {
        // Given
        let url = URL(string: "http://duckduckgo.com/subscriptions/welcome")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertFalse(result, "HTTP requests should be rejected to prevent token exposure over insecure connections")
    }

    func testCanPageRequestToken_HTTPSScheme_ReturnsTrue() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/welcome")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "HTTPS requests should be allowed")
    }

    func testCanPageRequestToken_CustomScheme_ReturnsFalse() async throws {
        // Given
        let url = URL(string: "ddg://duckduckgo.com/subscriptions/welcome")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertFalse(result, "Custom URL schemes should be rejected")
    }

    // MARK: - Path Validation Tests

    func testCanPageRequestToken_InvalidPath_ReturnsFalse() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/invalid-path")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertFalse(result, "Invalid paths should be rejected")
    }

    func testCanPageRequestToken_PathWithTrailingSlash_HandledCorrectly() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/welcome/")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Trailing slash should be handled correctly")
    }

    func testCanPageRequestToken_PathNormalization_FiltersEmptyComponents() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions//welcome")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Empty path components should be filtered out")
    }

    // MARK: - Security Origin Tests

    func testCanPageRequestToken_SecurityOriginMismatch_ReturnsFalse() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/welcome")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: "different.com")

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertFalse(result, "Security origin mismatch should be rejected (XSS protection)")
    }

    func testCanPageRequestToken_SecurityOriginMatchesHost_ReturnsTrue() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/manage")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Matching security origin should be allowed")
    }

    // MARK: - Edge Cases

    func testCanPageRequestToken_DeepNestedPath_ValidatesCorrectly() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/activation-flow/this-device/activate-by-email/otp")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Deep nested valid paths should be allowed")
    }

    func testCanPageRequestToken_PlansPath_ReturnsTrue() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/subscriptions/plans")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Plans path should be allowed")
    }

    func testCanPageRequestToken_PlansPathWithTierQueryParameter_ReturnsTrue() async throws {
        // Given - upgradeToTier uses the same path as plans, just with a tier query parameter
        let url = URL(string: "https://duckduckgo.com/subscriptions/plans?tier=pro")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Plans path with tier query parameter should be allowed (query params are ignored in path validation)")
    }

    func testCanPageRequestToken_IdentityTheftRestorationPath_ReturnsTrue() async throws {
        // Given
        let url = URL(string: "https://duckduckgo.com/identity-theft-restoration")!
        let message = createMockMessage(url: url, isMainFrame: true, securityOriginHost: validHost)

        // When
        let result = await validator.canPageRequestToken(message)

        // Then
        XCTAssertTrue(result, "Identity theft restoration path should be allowed")
    }

    // MARK: - Helper Methods

    private func createMockMessage(url: URL?, isMainFrame: Bool, securityOriginHost: String) -> WKScriptMessage {
        let mockWebView = MockWKWebView(url: url)
        let mockFrameInfo = WKFrameInfo.mock(isMainFrame: isMainFrame, securityOriginHost: securityOriginHost, webView: mockWebView)
        return WKScriptMessage.mock(webView: mockWebView, frameInfo: mockFrameInfo)
    }
}
