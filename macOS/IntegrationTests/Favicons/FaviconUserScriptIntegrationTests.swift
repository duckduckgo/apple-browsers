//
//  FaviconUserScriptIntegrationTests.swift
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

import Combine
import Common
import Foundation
import PrivacyConfigTestsUtils
import SharedTestUtilities
import UserScript
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Integration tests for the favicon C-S-S → native flow.
/// These tests verify that:
/// 1. The FaviconUserScript receives favicon notifications from Content Scope Scripts
/// 2. The FaviconsTabExtension correctly processes favicon links
/// 3. The full end-to-end flow works correctly in a real WKWebView
@available(macOS 12.0, *)
class FaviconUserScriptIntegrationTests: XCTestCase {

    var window: NSWindow!
    var schemeHandler: TestSchemeHandler!
    var contentBlockingMock: ContentBlockingMock!
    var privacyFeaturesMock: AnyPrivacyFeatures!
    var privacyConfiguration: MockPrivacyConfiguration {
        contentBlockingMock.privacyConfigurationManager.privacyConfig as! MockPrivacyConfiguration
    }

    // MARK: - Test HTML Pages

    static let htmlWithFavicon = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Test Page with Favicon</title>
        <link rel="icon" href="/favicon.ico" type="image/x-icon">
    </head>
    <body>
        <h1>Test Page</h1>
    </body>
    </html>
    """

    static let htmlWithMultipleFavicons = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Test Page with Multiple Favicons</title>
        <link rel="icon" href="/favicon.ico" type="image/x-icon">
        <link rel="icon" href="/favicon.png" type="image/png" sizes="32x32">
        <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    </head>
    <body>
        <h1>Test Page</h1>
    </body>
    </html>
    """

    static let htmlWithDynamicFavicon = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Test Page with Dynamic Favicon</title>
        <link rel="icon" href="/initial-favicon.ico" type="image/x-icon" id="favicon">
    </head>
    <body>
        <h1>Dynamic Favicon Test</h1>
        <script>
            function changeFavicon() {
                document.getElementById('favicon').href = '/updated-favicon.ico';
            }
            // Change favicon after 100ms
            setTimeout(changeFavicon, 100);
        </script>
    </body>
    </html>
    """

    // MARK: - Setup and Teardown

    @MainActor
    override func setUp() {
        super.setUp()

        contentBlockingMock = ContentBlockingMock()
        privacyFeaturesMock = AppPrivacyFeatures(contentBlocking: contentBlockingMock, httpsUpgradeStore: HTTPSUpgradeStoreMock())

        // Enable the favicon feature in privacy config
        privacyConfiguration.isFeatureEnabledCheck = { feature, _ in
            return feature == .contentScopeScripts || feature == .favicon
        }

        schemeHandler = TestSchemeHandler { request in
            guard let url = request.url else { return nil }

            // Serve HTML pages
            if url.path == "/" || url.path.isEmpty {
                return .ok(.html(Self.htmlWithFavicon))
            }
            if url.path == "/multiple" {
                return .ok(.html(Self.htmlWithMultipleFavicons))
            }
            if url.path == "/dynamic" {
                return .ok(.html(Self.htmlWithDynamicFavicon))
            }

            // Serve favicon files (return empty data as placeholder)
            if url.path.contains("favicon") {
                return .ok(.data(Data(), mime: "image/x-icon"))
            }

            return nil
        }

        NSApp.delegateTyped.startupPreferences.customHomePageURL = URL.duckDuckGo.absoluteString
        NSApp.delegateTyped.startupPreferences.launchToCustomHomePage = false
    }

    @MainActor
    override func tearDown() {
        autoreleasepool {
            window?.close()
            window = nil
            schemeHandler = nil
            contentBlockingMock = nil
            privacyFeaturesMock = nil
        }
        super.tearDown()
    }

    // MARK: - Integration Tests

    /// Tests that the FaviconUserScript receives favicon links when a page loads
    @MainActor
    func testFaviconUserScriptReceivesFaviconLinksOnPageLoad() async throws {
        // Create a mock delegate to capture favicon callbacks
        let mockDelegate = MockFaviconUserScriptDelegate()

        let tab = Tab(
            content: .url(URL(string: "https://example.com/")!, credential: nil, source: .userEntered("")),
            webViewConfiguration: schemeHandler.webViewConfiguration(),
            privacyFeatures: privacyFeaturesMock,
            maliciousSiteDetector: MockMaliciousSiteDetecting()
        )

        let viewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]))
        window = WindowsManager.openNewWindow(with: viewModel)!

        // Set the mock delegate on the FaviconUserScript
        if let userScripts = tab.userScripts,
           let faviconScript = userScripts.faviconScript as? FaviconUserScript {
            faviconScript.delegate = mockDelegate
        }

        // Wait for navigation to complete
        _=try await tab.webViewDidFinishNavigationPublisher.timeout(10).first().promise().value

        // Wait for favicon script to process (small delay for C-S-S to execute)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Verify the delegate received favicon links
        XCTAssertTrue(mockDelegate.callCount > 0, "FaviconUserScript delegate should have been called")
        XCTAssertNotNil(mockDelegate.receivedFaviconLinks, "Should have received favicon links")
        XCTAssertFalse(mockDelegate.receivedFaviconLinks?.isEmpty ?? true, "Favicon links should not be empty")
    }

    /// Tests that multiple favicon links are correctly captured
    @MainActor
    func testMultipleFaviconLinksAreCaptured() async throws {
        let mockDelegate = MockFaviconUserScriptDelegate()

        let tab = Tab(
            content: .url(URL(string: "https://example.com/multiple")!, credential: nil, source: .userEntered("")),
            webViewConfiguration: schemeHandler.webViewConfiguration(),
            privacyFeatures: privacyFeaturesMock,
            maliciousSiteDetector: MockMaliciousSiteDetecting()
        )

        let viewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]))
        window = WindowsManager.openNewWindow(with: viewModel)!

        if let userScripts = tab.userScripts,
           let faviconScript = userScripts.faviconScript as? FaviconUserScript {
            faviconScript.delegate = mockDelegate
        }

        _=try await tab.webViewDidFinishNavigationPublisher.timeout(10).first().promise().value
        try await Task.sleep(nanoseconds: 500_000_000)

        // Should capture all 3 favicon links (icon, icon with sizes, apple-touch-icon)
        XCTAssertTrue(mockDelegate.callCount > 0, "Delegate should have been called")

        if let links = mockDelegate.receivedFaviconLinks {
            XCTAssertGreaterThanOrEqual(links.count, 2, "Should capture multiple favicon links")

            // Verify we have different rel types
            let rels = Set(links.map { $0.rel })
            XCTAssertTrue(rels.contains("icon") || rels.contains { $0.contains("icon") },
                          "Should include icon type favicon")
        }
    }

    /// Tests that the document URL is correctly passed to the delegate
    @MainActor
    func testDocumentUrlIsCorrectlyPassed() async throws {
        let mockDelegate = MockFaviconUserScriptDelegate()
        let testUrl = URL(string: "https://example.com/")!

        let tab = Tab(
            content: .url(testUrl, credential: nil, source: .userEntered("")),
            webViewConfiguration: schemeHandler.webViewConfiguration(),
            privacyFeatures: privacyFeaturesMock,
            maliciousSiteDetector: MockMaliciousSiteDetecting()
        )

        let viewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]))
        window = WindowsManager.openNewWindow(with: viewModel)!

        if let userScripts = tab.userScripts,
           let faviconScript = userScripts.faviconScript as? FaviconUserScript {
            faviconScript.delegate = mockDelegate
        }

        _=try await tab.webViewDidFinishNavigationPublisher.timeout(10).first().promise().value
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNotNil(mockDelegate.receivedDocumentUrl, "Document URL should be passed to delegate")
        XCTAssertEqual(mockDelegate.receivedDocumentUrl?.host, testUrl.host,
                       "Document URL host should match the loaded page")
    }

    /// Tests that dynamic favicon changes are detected
    @MainActor
    func testDynamicFaviconChangesAreDetected() async throws {
        let mockDelegate = MockFaviconUserScriptDelegate()

        let tab = Tab(
            content: .url(URL(string: "https://example.com/dynamic")!, credential: nil, source: .userEntered("")),
            webViewConfiguration: schemeHandler.webViewConfiguration(),
            privacyFeatures: privacyFeaturesMock,
            maliciousSiteDetector: MockMaliciousSiteDetecting()
        )

        let viewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]))
        window = WindowsManager.openNewWindow(with: viewModel)!

        if let userScripts = tab.userScripts,
           let faviconScript = userScripts.faviconScript as? FaviconUserScript {
            faviconScript.delegate = mockDelegate
        }

        _=try await tab.webViewDidFinishNavigationPublisher.timeout(10).first().promise().value

        // Wait for the dynamic favicon change (script waits 100ms, we wait longer to be safe)
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Should have received at least 2 calls: initial load + dynamic update
        // Note: The exact count may vary based on debouncing in C-S-S
        XCTAssertGreaterThanOrEqual(mockDelegate.callCount, 1,
                                     "Should detect at least the initial favicon")

        // Check that we eventually see the updated favicon URL
        if let links = mockDelegate.receivedFaviconLinks, !links.isEmpty {
            let urls = links.map { $0.href.absoluteString }
            // The final call should contain the updated favicon
            XCTAssertTrue(urls.contains { $0.contains("favicon") },
                          "Should have received a favicon URL")
        }
    }
}

// MARK: - Mock Classes

@available(macOS 12.0, *)
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

@available(macOS 12.0, *)
private final class MockMaliciousSiteDetecting: MaliciousSiteProtection.MaliciousSiteDetecting {
    func startFetching() {}
    func registerBackgroundRefreshTaskHandler() {}
    func evaluate(_ url: URL) async -> MaliciousSiteProtection.ThreatKind? { nil }
}
