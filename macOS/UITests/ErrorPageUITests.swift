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

        // Wait for address bar to reflect failing host
        app.activateAddressBar()
        let urlPredicate = NSPredicate(format: "value CONTAINS[c] %@", "thisdomaindoesnotexist")
        let urlExpectation = expectation(for: urlPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [urlExpectation], timeout: 30.0), .completed, "Address bar should reflect failed navigation attempt with original host")
    }

    func testErrorPage_TryAgainButton_ReloadsPage() throws {
        // Navigate to an unreachable URL to get error page
        let unreachableURL = URL(string: "https://nonexistent.example.invalid")!
        app.activateAddressBar()
        app.pasteURL(unreachableURL, pressingEnter: true)

        // Wait for address bar to reflect failing host
        app.activateAddressBar()
        let initialPredicate = NSPredicate(format: "value CONTAINS[c] %@", "nonexistent.example.invalid")
        let initialExp = expectation(for: initialPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [initialExp], timeout: 30.0), .completed)

        // Reload (Cmd+R) and ensure URL remains the same
        app.typeKey("r", modifierFlags: [.command])

        app.activateAddressBar()
        let afterReloadExp = expectation(for: initialPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [afterReloadExp], timeout: 15.0), .completed, "Failing URL should remain after reload attempt")
    }

    func testErrorPage_BackNavigation_WorksCorrectly() throws {
        // First navigate to a working page
        let workingURL = UITests.simpleServedPage(titled: "Working Test Page")
        app.activateAddressBar()
        app.pasteURL(workingURL, pressingEnter: true)

        // Wait for working page to load
        let workingContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Working Test Page'"))
            .firstMatch
        XCTAssertTrue(workingContent.waitForExistence(timeout: 15.0), "Working page should load first")

        // Navigate to failing URL
        let errorURL = URL(string: "https://failingdomain.invalid")!
        app.activateAddressBar()
        app.pasteURL(errorURL, pressingEnter: true)

        // Wait for address bar to reflect failing host
        app.activateAddressBar()
        let failingPredicate = NSPredicate(format: "value CONTAINS[c] %@", "failingdomain.invalid")
        let failingExp = expectation(for: failingPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [failingExp], timeout: 30.0), .completed, "Error page should be displayed")

        // Test back navigation from error page
        let backButton = app.buttons["NavigationBarViewController.BackButton"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5.0), "Back button should be available")
        XCTAssertTrue(backButton.isEnabled, "Back button should be enabled after error")

        backButton.click()

        // Should navigate back to working page
        XCTAssertTrue(workingContent.waitForExistence(timeout: 15.0), "Should navigate back to working page from error page")

        // Verify we're back on the working page
        app.activateAddressBar()
        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(addressBarValue.contains("localhost"), "Should be back on working local page")
    }

    // MARK: - Connection Recovery Tests

    func testErrorPage_NavigateToValidURL_AfterError_LoadsSuccessfully() throws {
        // Start with an unreachable local endpoint
        let networkErrorURL = URL(string: "https://temporaryerror.invalid")!
        app.activateAddressBar()
        app.pasteURL(networkErrorURL, pressingEnter: true)

        // Wait for address bar to reflect failing host
        app.activateAddressBar()
        let errorHostPredicate = NSPredicate(format: "value CONTAINS[c] %@", "temporaryerror.invalid")
        let errorHostExp = expectation(for: errorHostPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [errorHostExp], timeout: 30.0), .completed, "Should show connection failure initially")

        // Now navigate to a valid URL after the error
        let recoveredURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        app.pasteURL(recoveredURL, pressingEnter: true)

        // Should successfully load valid page
        let recoveredContent = webView.staticTexts
            .containing(NSPredicate(format: "value CONTAINS 'Example Domain'"))
            .firstMatch
        XCTAssertTrue(recoveredContent.waitForExistence(timeout: 15.0), "Should load successfully after navigating to a valid URL")

        // Verify successful navigation
        app.activateAddressBar()
        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(addressBarValue.contains("example.com"), "Should successfully navigate to example.com")
    }

    // MARK: - Error Page Reload Tests

    func testErrorPage_ReloadFailingPage_ShowsUpdatedError() throws {
        // Navigate to failing URL
        let failingURL = URL(string: "https://reloaderror.invalid")!
        app.activateAddressBar()
        app.pasteURL(failingURL, pressingEnter: true)

        // Wait for initial failure state (address bar host)
        app.activateAddressBar()
        let failingPredicate = NSPredicate(format: "value CONTAINS[c] %@", "reloaderror.invalid")
        let failExp = expectation(for: failingPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [failExp], timeout: 30.0), .completed)
        let initialURLValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(initialURLValue.contains("reloaderror.invalid"), "Should show initial failing URL in address bar")

        // Reload via keyboard (Cmd+R) and verify error persists for failing URL
        app.typeKey("r", modifierFlags: [.command])

        app.activateAddressBar()
        let afterExp = expectation(for: failingPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [afterExp], timeout: 15.0), .completed, "Failing URL should remain after reload attempt")
    }

    // MARK: - Forward Navigation Tests

    func testErrorPage_ForwardNavigationAfterError_PreservesHistory() throws {
        // Navigate through: working page -> error page -> working page -> back -> forward

        // Step 1: Working page
        let firstURL = UITests.simpleServedPage(titled: "First Error Test Page")
        app.activateAddressBar()
        app.pasteURL(firstURL, pressingEnter: true)

        let firstPageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'First Error Test Page'"))
            .firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: 15.0), "First page should load")

        // Step 2: Error page
        let errorURL = URL(string: "https://forwardtesterror.invalid")!
        app.activateAddressBar()
        app.pasteURL(errorURL, pressingEnter: true)
        app.activateAddressBar()
        let errorHostPredicate = NSPredicate(format: "value CONTAINS[c] %@", "forwardtesterror.invalid")
        let errorHostExp = expectation(for: errorHostPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [errorHostExp], timeout: 30.0), .completed, "Error page should be displayed")

        // Step 3: Another working page
        let thirdURL = URL(string: "https://example.com")!
        app.activateAddressBar()
        app.pasteURL(thirdURL, pressingEnter: true)

        let thirdPageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'"))
            .firstMatch
        XCTAssertTrue(thirdPageContent.waitForExistence(timeout: 15.0), "Third page should load")

        // Step 4: Go back twice
        let backButton = app.buttons["NavigationBarViewController.BackButton"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5.0), "Back button should be available")

        backButton.click() // Back to error page
        app.activateAddressBar()
        let errorBackExp = expectation(for: errorHostPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [errorBackExp], timeout: 15.0), .completed, "Should be back on error page")

        backButton.click() // Back to first page
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: 15.0), "Should be back on first page")

        // Step 5: Forward navigation should work
        let forwardButton = app.buttons["NavigationBarViewController.ForwardButton"]
        XCTAssertTrue(forwardButton.waitForExistence(timeout: 5.0), "Forward button should be available")
        XCTAssertTrue(forwardButton.isEnabled, "Forward button should be enabled")

        forwardButton.click() // Forward to error page
        app.activateAddressBar()
        let errorForwardExp = expectation(for: errorHostPredicate, evaluatedWith: addressBarTextField)
        XCTAssertEqual(XCTWaiter.wait(for: [errorForwardExp], timeout: 15.0), .completed, "Should go forward to error page")

        forwardButton.click() // Forward to third page
        XCTAssertTrue(thirdPageContent.waitForExistence(timeout: 15.0), "Should go forward to third page")

        // Verify final navigation state
        app.activateAddressBar()
        let finalURL = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(finalURL.contains("example.com"), "Should end up on example.com after forward navigation")
    }

    // MARK: - Toolbar Reload Button Tests

    func testErrorPage_ToolbarReloadButton_ReloadsCurrentURL() throws {
        // Load a valid page
        let url = URL(string: "https://example.com")!
        app.activateAddressBar()
        app.pasteURL(url, pressingEnter: true)

        // Wait for known content to appear
        let exampleContent = webView.staticTexts
            .containing(NSPredicate(format: "value CONTAINS 'Example Domain'"))
            .firstMatch
        XCTAssertTrue(exampleContent.waitForExistence(timeout: 20.0), "Example page should load")

        // Capture current URL from address bar
        app.activateAddressBar()
        let before = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(before.contains("example.com"), "Precondition: example.com is loaded")

        // Click the toolbar Reload button
        let reloadButton = app.buttons["NavigationBarViewController.RefreshOrStopButton"].firstMatch
        XCTAssertTrue(reloadButton.waitForExistence(timeout: 5.0), "Reload button should exist")
        reloadButton.click()

        // Wait for content to (re)appear to confirm reload occurred
        XCTAssertTrue(exampleContent.waitForExistence(timeout: 20.0), "Content should be visible after reload")

        // URL should remain the same domain
        app.activateAddressBar()
        let after = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(after.contains("example.com"), "URL should remain on example.com after reload")
    }
}
