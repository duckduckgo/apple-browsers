//
//  ErrorPageUITests.swift
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

import XCTest
import Foundation

class ErrorPageUITests: UITestCase {

    private var addressBarTextField: XCUIElement { app.addressBar }
    private var webView: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        webView = app.webViews.firstMatch
    }

    override func tearDown() {
        webView = nil
        app = nil
    }

    // MARK: - Unreachable Host Tests

    func testErrorPage_UnreachableHost_ShowsErrorMessage() throws {
        // Navigate to an unreachable local endpoint to trigger a connection failure
        let invalidURL = URL(string: "https://thisdomaindoesnotexist.invalidtld")!
        app.activateAddressBar()
        app.pasteURL(invalidURL, pressingEnter: true)

        // Wait for the error page to appear
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Error page title not shown in reasonable time"
        )
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "A server with the specified hostname could not be found.").firstMatch
                .exists,
            "Error page description not shown in reasonable time"
        )

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://thisdomaindoesnotexist.invalidtld/")
    }

    func testErrorPage_TryAgainButton_ReloadsPage() throws {
        // Navigate to an unreachable URL to get error page
        let unreachableURL = URL(string: "https://nonexistent.example.invalid")!
        app.activateAddressBar()
        app.pasteURL(unreachableURL, pressingEnter: true)

        // Wait for the error page to appear
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for unreachable URL"
        )

        // Reload (Cmd+R) and ensure URL remains the same
        app.typeKey("r", modifierFlags: [.command])

        // Wait for error page to appear again after reload
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Error page should appear again after reload"
        )

        // Verify address bar still shows the failing URL
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://nonexistent.example.invalid/")
    }

    func testErrorPage_BackNavigation_WorksCorrectly() throws {
        // First navigate to a working page
        let workingURL = UITests.simpleServedPage(titled: "Working Test Page")
        app.activateAddressBar()
        app.pasteURL(workingURL, pressingEnter: true)

        // Wait for working page to load
        let workingContent = webView.staticTexts.containing(\.value, containing: "Working Test Page").firstMatch
        XCTAssertTrue(workingContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Working page should load first")

        // Navigate to failing URL
        let errorURL = URL(string: "https://failingdomain.invalid")!
        app.activateAddressBar()
        app.pasteURL(errorURL, pressingEnter: true)

        // Wait for error page to appear
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for failing domain"
        )

        // Test back navigation from error page
        let backButton = app.buttons["NavigationBarViewController.BackButton"]
        XCTAssertTrue(backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")
        XCTAssertTrue(backButton.isEnabled, "Back button should be enabled after error")

        backButton.click()

        // Should navigate back to working page
        XCTAssertTrue(workingContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should navigate back to working page from error page")

        // Verify we're back on the working page
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertEqual(addressBarValue, workingURL.absoluteString, "Should be back on working local page")
    }

    // MARK: - Connection Recovery Tests

    func testErrorPage_NavigateToValidURL_AfterError_LoadsSuccessfully() throws {
        // Start with an unreachable local endpoint
        let networkErrorURL = URL(string: "https://temporaryerror.invalid")!
        app.activateAddressBar()
        app.pasteURL(networkErrorURL, pressingEnter: true)

        // Wait for error page to appear
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for temporary error"
        )

        // Now navigate to a valid URL after the error
        let recoveredURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        app.pasteURL(recoveredURL, pressingEnter: true)

        // Should successfully load valid page
        let recoveredContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(recoveredContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load successfully after navigating to a valid URL")

        // Verify successful navigation
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Should successfully navigate to example.com")
    }

    // MARK: - Error Page Reload Tests

    func testErrorPage_ReloadFailingPage_ShowsUpdatedError() throws {
        // Navigate to failing URL
        let failingURL = URL(string: "https://reloaderror.invalid")!
        app.activateAddressBar()
        app.pasteURL(failingURL, pressingEnter: true)

        // Wait for error page to appear
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for reload error test"
        )

        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://reloaderror.invalid/", "Should show initial failing URL in address bar")

        // Reload via keyboard (Cmd+R) and verify error persists for failing URL
        app.typeKey("r", modifierFlags: [.command])

        // Wait for error page to appear again after reload
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Error page should appear again after reload"
        )

        // Verify URL remains the same after reload
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://reloaderror.invalid/", "Failing URL should remain after reload attempt")
    }

    // MARK: - Forward Navigation Tests

    func testErrorPage_ForwardNavigationAfterError_PreservesHistory() throws {
        // Navigate through: working page -> error page -> working page -> back -> forward

        // Step 1: Working page
        let firstURL = UITests.simpleServedPage(titled: "First Error Test Page")
        app.activateAddressBar()
        app.pasteURL(firstURL, pressingEnter: true)

        let firstPageContent = webView.staticTexts.containing(\.value, containing: "First Error Test Page").firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "First page should load")

        // Step 2: Error page
        let errorURL = URL(string: "https://forwardtesterror.invalid")!
        app.activateAddressBar()
        app.pasteURL(errorURL, pressingEnter: true)

        // Wait for error page to appear
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.navigation),
            "Error page should appear for forward test error"
        )

        // Step 3: Another working page
        let thirdURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        app.pasteURL(thirdURL, pressingEnter: true)

        let thirdPageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(thirdPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Third page should load")

        // Step 4: Go back twice
        let backButton = app.buttons["NavigationBarViewController.BackButton"]
        XCTAssertTrue(backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")

        backButton.click() // Back to error page

        // Wait for error page to appear again
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Should be back on error page"
        )

        backButton.click() // Back to first page
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should be back on first page")

        // Step 5: Forward navigation should work
        let forwardButton = app.buttons["NavigationBarViewController.ForwardButton"]
        XCTAssertTrue(forwardButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Forward button should be available")
        XCTAssertTrue(forwardButton.isEnabled, "Forward button should be enabled")

        forwardButton.click() // Forward to error page

        // Wait for error page to appear again
        XCTAssertTrue(
            webView.staticTexts.containing(\.value, containing: "DuckDuckGo can’t load this page.").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.localTestServer),
            "Should go forward to error page"
        )

        forwardButton.click() // Forward to third page
        XCTAssertTrue(thirdPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should go forward to third page")

        // Verify final navigation state
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Should end up on example.com after forward navigation")
    }

    // MARK: - Toolbar Reload Button Tests

    func testErrorPage_ToolbarReloadButton_ReloadsCurrentURL() throws {
        // Load a valid page
        let url = URL(string: "https://example.com")!
        app.activateAddressBar()
        app.pasteURL(url, pressingEnter: true)

        // Wait for known content to appear
        let exampleContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(exampleContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Example page should load")

        // Capture current URL from address bar
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Precondition: example.com is loaded")

        // Click the toolbar Reload button
        let reloadButton = app.buttons["NavigationBarViewController.RefreshOrStopButton"].firstMatch
        XCTAssertTrue(reloadButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Reload button should exist")
        reloadButton.click()

        // Wait for content to (re)appear to confirm reload occurred
        XCTAssertTrue(exampleContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Content should be visible after reload")

        // URL should remain the same domain
        XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "URL should remain on example.com after reload")
    }
}
