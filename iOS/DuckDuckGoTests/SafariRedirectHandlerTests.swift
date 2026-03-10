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
import UIKit
import Common
import BrowserServicesKit
@testable import DuckDuckGo

final class SafariRedirectHandlerTests: XCTestCase {

    private var handler: SafariRedirectHandler!
    private var delegate: MockSafariRedirectHandlerDelegate!

    private let xSafariURL = URL(string: "x-safari-https://example.com/page")!
    private let httpsURL = URL(string: "https://example.com/page")!
    private let regularURL = URL(string: "https://example.com/other")!

    override func setUp() {
        super.setUp()
        handler = SafariRedirectHandler(tld: TLD(), featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.customXSafariRedirectHandling]))
        delegate = MockSafariRedirectHandlerDelegate()
        handler.delegate = delegate
    }

    // MARK: - Non x-safari-https URLs

    func testHandleRedirectReturnsFalseForNonXSafariScheme() {
        XCTAssertFalse(handler.handleRedirect(to: regularURL))
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testHandleRedirectReturnsFalseForHTTPScheme() {
        let httpURL = URL(string: "http://example.com/page")!
        XCTAssertFalse(handler.handleRedirect(to: httpURL))
    }

    func testHandleRedirectReturnsFalseWhenFeatureFlagDisabled() {
        let disabledHandler = SafariRedirectHandler(tld: TLD(), featureFlagger: MockFeatureFlagger())
        let mockDelegate = MockSafariRedirectHandlerDelegate()
        disabledHandler.delegate = mockDelegate

        XCTAssertFalse(disabledHandler.handleRedirect(to: xSafariURL))
        XCTAssertTrue(mockDelegate.presentedAlerts.isEmpty)
    }

    // MARK: - First redirect shows Alert 1

    func testFirstRedirectShowsTryOpenAlert() {
        XCTAssertTrue(handler.handleRedirect(to: xSafariURL))
        XCTAssertEqual(delegate.presentedAlerts.count, 1)
        XCTAssertEqual(delegate.presentedAlerts.first?.title, UserText.xSafariHTTPSTryOpenTitle)
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testFirstRedirectDoesNotLoadOrOpenExternally() {
        _ = handler.handleRedirect(to: xSafariURL)
        XCTAssertTrue(delegate.loadedURLs.isEmpty)
        XCTAssertTrue(delegate.openedExternallyURLs.isEmpty)
    }

    func testRedirectsWhileAlertShowingAreConsumedSilently() {
        _ = handler.handleRedirect(to: xSafariURL) // Shows alert
        XCTAssertTrue(handler.handleRedirect(to: xSafariURL)) // Consumed
        XCTAssertTrue(handler.handleRedirect(to: xSafariURL)) // Consumed

        XCTAssertEqual(delegate.presentedAlerts.count, 1) // No extra alerts
        XCTAssertTrue(delegate.loadedURLs.isEmpty) // No silent loads
    }

    // MARK: - "Stay in DuckDuckGo" flow

    func testStayActionConvertsToHTTPSAndLoads() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // "Stay in DuckDuckGo" (cancel style, first added)

        XCTAssertEqual(delegate.loadedURLs.count, 1)
        XCTAssertEqual(delegate.loadedURLs.first?.scheme, "https")
        XCTAssertEqual(delegate.loadedURLs.first?.host, "example.com")
    }

    func testAfterStaySubsequentRedirectsSilentlyConvert() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay

        // Next two redirects should silently convert
        XCTAssertTrue(handler.handleRedirect(to: xSafariURL))
        XCTAssertEqual(delegate.loadedURLs.count, 2)
        XCTAssertEqual(delegate.presentedAlerts.count, 1) // No new alert

        XCTAssertTrue(handler.handleRedirect(to: xSafariURL))
        XCTAssertEqual(delegate.loadedURLs.count, 3)
        XCTAssertEqual(delegate.presentedAlerts.count, 1)
    }

    func testAfterStayThirdRedirectShowsLoopAlert() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay

        _ = handler.handleRedirect(to: xSafariURL) // count 1
        _ = handler.handleRedirect(to: xSafariURL) // count 2
        _ = handler.handleRedirect(to: xSafariURL) // count 3 → loop

        XCTAssertEqual(delegate.presentedAlerts.count, 2)
        XCTAssertEqual(delegate.presentedAlerts.last?.title, UserText.xSafariHTTPSLoopTitle)
    }

    func testRedirectsWhileLoopAlertShowingAreConsumedSilently() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay

        _ = handler.handleRedirect(to: xSafariURL) // count 1
        _ = handler.handleRedirect(to: xSafariURL) // count 2
        _ = handler.handleRedirect(to: xSafariURL) // count 3 → loop alert

        XCTAssertEqual(delegate.presentedAlerts.count, 2)

        // Additional redirects while loop alert is showing should be consumed silently
        XCTAssertTrue(handler.handleRedirect(to: xSafariURL))
        XCTAssertTrue(handler.handleRedirect(to: xSafariURL))

        XCTAssertEqual(delegate.presentedAlerts.count, 2) // No extra alerts
        XCTAssertEqual(delegate.loadedURLs.count, 3) // No extra loads (1 from Stay + 2 silent converts)
    }

    // MARK: - "Open in Safari" flow

    func testOpenInSafariDelegatesExternalOpen() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 1, ofAlert: 0) // "Open in Safari"

        XCTAssertEqual(delegate.openedExternallyURLs.count, 1)
        XCTAssertEqual(delegate.openedExternallyURLs.first, xSafariURL)
    }

    func testOpenInSafariResetsAlertShownForNextRedirect() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 1, ofAlert: 0) // Open in Safari

        // Next redirect should show Alert 1 again
        _ = handler.handleRedirect(to: xSafariURL)
        XCTAssertEqual(delegate.presentedAlerts.count, 2)
        XCTAssertEqual(delegate.presentedAlerts.last?.title, UserText.xSafariHTTPSTryOpenTitle)
    }

    func testOpenInSafariDoesNotMarkAsSuppressed() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 1, ofAlert: 0) // "Open in Safari"

        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    // MARK: - Loop alert actions

    func testLoopAlertGoBackDelegatesAndResetsState() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay
        _ = handler.handleRedirect(to: xSafariURL)
        _ = handler.handleRedirect(to: xSafariURL)
        _ = handler.handleRedirect(to: xSafariURL) // Loop alert

        delegate.tapAlertAction(at: 0, ofAlert: 1) // "Go Back"
        XCTAssertTrue(delegate.goBackRequested)

        // After go back, next redirect should show Alert 1 again
        _ = handler.handleRedirect(to: xSafariURL)
        XCTAssertEqual(delegate.presentedAlerts.count, 3)
        XCTAssertEqual(delegate.presentedAlerts.last?.title, UserText.xSafariHTTPSTryOpenTitle)
    }

    func testLoopAlertOpenInSafariDelegates() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay
        _ = handler.handleRedirect(to: xSafariURL)
        _ = handler.handleRedirect(to: xSafariURL)
        _ = handler.handleRedirect(to: xSafariURL) // Loop alert

        delegate.tapAlertAction(at: 1, ofAlert: 1) // "Open in Safari"
        XCTAssertEqual(delegate.openedExternallyURLs.count, 1)
    }

    func testLoopAlertOpenInSafariResetsStateForFreshAlert() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay
        _ = handler.handleRedirect(to: xSafariURL)
        _ = handler.handleRedirect(to: xSafariURL)
        _ = handler.handleRedirect(to: xSafariURL) // Loop alert

        delegate.tapAlertAction(at: 1, ofAlert: 1) // "Open in Safari"

        // Next redirect should show Alert 1 again, not loop alert
        _ = handler.handleRedirect(to: xSafariURL)
        XCTAssertEqual(delegate.presentedAlerts.count, 3)
        XCTAssertEqual(delegate.presentedAlerts.last?.title, UserText.xSafariHTTPSTryOpenTitle)
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    // MARK: - Suppress branch loop detection

    func testSuppressBranchDetectsLoopWhenAlertDismissedWithoutStay() {
        // First redirect shows alert
        _ = handler.handleRedirect(to: xSafariURL)
        // Simulate: alert shown but user chose "Open in Safari" — alertShown reset
        delegate.tapAlertAction(at: 1, ofAlert: 0)

        // Show alert again
        _ = handler.handleRedirect(to: xSafariURL)
        // This time user taps Stay
        delegate.tapAlertAction(at: 0, ofAlert: 1)

        // Now stayEnabled, subsequent redirects count
        _ = handler.handleRedirect(to: xSafariURL) // 1
        _ = handler.handleRedirect(to: xSafariURL) // 2
        _ = handler.handleRedirect(to: xSafariURL) // 3 → loop
        XCTAssertEqual(delegate.presentedAlerts.count, 3) // alert1, alert1 again, loop alert
    }

    // MARK: - Per-host scoping

    func testDifferentHostGetsFreshAlert() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay on example.com

        let otherHostURL = URL(string: "x-safari-https://other.com/page")!
        _ = handler.handleRedirect(to: otherHostURL)

        // Should show Alert 1 for the new host
        XCTAssertEqual(delegate.presentedAlerts.count, 2)
        XCTAssertEqual(delegate.presentedAlerts.last?.title, UserText.xSafariHTTPSTryOpenTitle)
    }

    func testSuppressedRedirectTrackedPerHost() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay on example.com

        let otherHostURL = URL(string: "x-safari-https://other.com/page")!
        _ = handler.handleRedirect(to: otherHostURL)
        delegate.tapAlertAction(at: 0, ofAlert: 1) // Stay on other.com

        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: URL(string: "https://other.com/page")!))
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: URL(string: "https://unrelated.com")!))
    }

    func testSubdomainRedirectMatchesParentDomain() {
        let subdomainURL = URL(string: "x-safari-https://redirect.example.com/page")!
        _ = handler.handleRedirect(to: subdomainURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay

        // Breakage report for example.com should detect the suppressed redirect
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))

        handler.reset()

        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))

        // After reset, should show Alert 1 fresh
        _ = handler.handleRedirect(to: xSafariURL)
        XCTAssertEqual(delegate.presentedAlerts.count, 2)
        XCTAssertEqual(delegate.presentedAlerts.last?.title, UserText.xSafariHTTPSTryOpenTitle)
    }

    func testResetMidLoopStartsFresh() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay
        _ = handler.handleRedirect(to: xSafariURL) // count 1
        _ = handler.handleRedirect(to: xSafariURL) // count 2

        handler.reset()

        // Fresh start — should show Alert 1
        _ = handler.handleRedirect(to: xSafariURL)
        XCTAssertEqual(delegate.presentedAlerts.last?.title, UserText.xSafariHTTPSTryOpenTitle)
    }

    // MARK: - isAfterSuppressedXSafariRedirect

    func testIsAfterSuppressedXSafariRedirectPersistsAcrossMultipleRedirects() {
        _ = handler.handleRedirect(to: xSafariURL)
        delegate.tapAlertAction(at: 0, ofAlert: 0) // Stay
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))

        _ = handler.handleRedirect(to: xSafariURL)
        XCTAssertTrue(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testIsAfterSuppressedXSafariRedirectFalseByDefault() {
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: httpsURL))
    }

    func testIsAfterSuppressedXSafariRedirectFalseForDifferentHost() {
        _ = handler.handleRedirect(to: xSafariURL)
        let differentHostURL = URL(string: "https://other.com/page")!
        XCTAssertFalse(handler.isAfterSuppressedXSafariRedirect(for: differentHostURL))
    }
}

// MARK: - Mock Delegate

private final class MockSafariRedirectHandlerDelegate: SafariRedirectHandlerDelegate {

    var loadedURLs: [URL] = []
    var openedExternallyURLs: [URL] = []
    var goBackRequested = false
    var presentedAlerts: [UIAlertController] = []

    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestLoadURL url: URL) {
        loadedURLs.append(url)
    }

    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestOpenExternallyURL url: URL) {
        openedExternallyURLs.append(url)
    }

    func safariRedirectHandlerDidRequestGoBack(_ handler: SafariRedirectHandling) {
        goBackRequested = true
    }

    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestPresentAlert alert: UIAlertController) {
        presentedAlerts.append(alert)
    }

    /// Tap an action by index on a specific alert.
    func tapAlertAction(at actionIndex: Int, ofAlert alertIndex: Int) {
        guard alertIndex < presentedAlerts.count else { return }
        let alert = presentedAlerts[alertIndex]
        guard actionIndex < alert.actions.count else { return }
        let action = alert.actions[actionIndex]
        // UIAlertAction handler is stored as a private property; use the typealias trick to invoke it
        typealias AlertHandler = @convention(block) (UIAlertAction) -> Void
        let key = "handler"
        guard let block = action.value(forKey: key) else { return }
        let handler = unsafeBitCast(block as AnyObject, to: AlertHandler.self)
        handler(action)
    }
}
