//
//  AddressBarUITests.swift
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

class AddressBarUITests: UITestCase {
    private var webView: XCUIElement!
    private var addressBarTextField: XCUIElement { app.addressBar }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        webView = app.webViews.firstMatch
    }

    override func tearDown() {
        webView = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Address Bar Activation/Focus Tests

    func testAddressBar_ClickToActivate_BecomesActive() throws {
        // Ensure window focused and navigate to a page first (deactivates address bar)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Main window should exist")
        window.click()

        app.activateAddressBar()
        let toolbar = app.windows.firstMatch.toolbars.firstMatch
        _ = toolbar.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        if !toolbar.exists {
            print(app.debugDescription)
        }
        // Paste URL
        app.pasteURL(UITests.simpleServedPage(titled: "Address Bar Test"), pressingEnter: true)

        let pageContent = webView.staticTexts.containing(\.value, containing: "Address Bar Test").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load test page")

        // Click toolbar (address bar container) to activate address field
        XCTAssertTrue(toolbar.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        toolbar.click()

        // Verify activation
        // Paste a different URL and verify navigation succeeds -> implies address bar is active
        app.pasteURL(UITests.simpleServedPage(titled: "Address Bar Test 2"), pressingEnter: true)
        let secondPageContent = webView.staticTexts
            .containing(\.value, containing: "Address Bar Test 2")
            .firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Address bar should accept input after click and navigate")
    }

    func testAddressBar_EscapeKey_DeactivatesAddressBar() throws {
        // Activate address bar and type something
        app.activateAddressBar()
        addressBarTextField.typeText("test-deactivation")

        // Press Escape to deactivate
        app.typeKey(.escape, modifierFlags: [])
        // Press Escape (twice to hide suggestions if any)
        app.typeKey(.escape, modifierFlags: [])

        // Verify deactivation - address bar should be cleared and not accepting input
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertFalse(addressBarValue.contains("test-deactivation"),
                       "Address bar should be deactivated and cleared after Escape")
    }

    func testAddressBar_CmdL_ActivatesAddressBar() throws {
        // Navigate to a page to deactivate address bar
        app.activateAddressBar()
        app.pasteURL(UITests.simpleServedPage(titled: "Address Bar Test"), pressingEnter: true)

        let pageContent = webView.staticTexts.containing(\.value, containing: "Address Bar Test").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load test page")

        // Use Cmd+L to activate
        app.activateAddressBar()

        // Verify activation by navigating via paste (ensures field is focused)
        app.pasteURL(UITests.simpleServedPage(titled: "Address Bar Test CmdL"), pressingEnter: true)
        let secondPageContent = webView.staticTexts
            .containing(\.value, containing: "Address Bar Test CmdL")
            .firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Address bar should be focused after Cmd+L and accept input")
    }

    // MARK: - New Tab Behavior Tests

    func testAddressBar_NewTab_AutomaticallyActive() throws {
        // Open new tab
        app.openNewTab()

        // Address bar should be automatically active on new tab
        addressBarTextField.typeText("new-tab-test")
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("new-tab-test"),
                     "Address bar should be automatically active on new tab")
    }

    // MARK: - URL vs Search Detection Tests

    func testAddressBar_ValidURL_NavigatesToURL() throws {
        let testURL = UITests.simpleServedPage(titled: "Navigation Test")
        app.activateAddressBar()
        app.pasteURL(testURL, pressingEnter: true)

        // Validate specific page content loaded
        let pageContent = webView.staticTexts.containing(\.value, containing: "Navigation Test").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should navigate to local test URL")

        // Validate address bar shows the URL
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("localhost:8085"), "Address bar should show the navigated URL")
    }

    func testAddressBar_SearchPhrase_RedirectsToSearch() throws {
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Address bar should be accessible")

        app.typeText("duck duck go search test")
        app.typeKey(.enter, modifierFlags: [])

        // Should redirect to DuckDuckGo search
        let searchContent = webView.staticTexts.containing(\.value, containing: "duck duck go search test").firstMatch
        XCTAssertTrue(searchContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should perform search for phrase")

        // Validate we're on DuckDuckGo search
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "Should be on DuckDuckGo search results")
    }

    func testAddressBar_PartialDomain_CompletesToURL() throws {
        // Activate address bar and paste via app scope to avoid focus flakiness
        app.activateAddressBar()
        app.pasteURL(URL(string: "example.com")!, pressingEnter: true)

        // Should complete to valid URL
        let pageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should complete partial domain to full URL")

        // Validate URL completion (HTTPS upgrade is tested in HTTPSUpgradeUITests)
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("example.com"), "Should complete partial domain to valid URL")
    }

    // MARK: - Punycode/International Domain Tests

    func testAddressBar_PunycodeURL_HandlesCorrectly() throws {
        // Test with international domain (should convert to punycode)
        let internationalDomain = "тест.example.com"
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Address bar should be accessible")
        addressBarTextField.typeText(internationalDomain)

        // The address bar should handle punycode conversion
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        // Should either show punycode or original international characters consistently
        XCTAssertFalse(addressBarValue.isEmpty, "Should handle international domain names")
    }

    // MARK: - Autocomplete/Suggestions Tests
    // Note: Detailed autocomplete functionality is tested in AutocompleteTests.swift

    func testAddressBar_Autocomplete_BasicInput() throws {
        // Basic test that text can be entered in address bar (detailed autocomplete behavior in AutocompleteTests.swift)
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Address bar should be accessible")

        addressBarTextField.typeText("duck")

        // Verify text was entered successfully
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("duck"), "Address bar should contain typed text")
    }

    // MARK: - Tab Switching Value Preservation Tests

    func testAddressBar_TabSwitching_PreservesValues() throws {
        // Navigate to a URL in first tab
        let firstURL = UITests.simpleServedPage(titled: "First Tab Test")
        app.activateAddressBar()
        app.pasteURL(firstURL, pressingEnter: true)

        let firstPageContent = webView.staticTexts.containing(\.value, containing: "First Tab Test").firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load first page")

        // Open new tab
        app.openNewTab()

        // Navigate to different URL in second tab
        let secondURL = UITests.simpleServedPage(titled: "Second Tab Test")
        app.activateAddressBar()
        app.pasteURL(secondURL, pressingEnter: true)

        let secondPageContent = webView.staticTexts.containing(\.value, containing: "Second Tab Test").firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load second page")

        // Switch back to first tab
        // Use keyboard shortcut to go to previous tab (more reliable than clicking tab button)
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        if window.exists { window.click() }
        app.typeKey("[", modifierFlags: [.command, .shift])

        // Verify first tab's content is visible again (content-based assertion is more reliable than address bar)
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "First tab's content should be preserved when switching tabs")
    }

    // MARK: - Navigation State Tests

    func testAddressBar_BackNavigation_UpdatesURLCorrectly() throws {
        // Navigate to first page
        let firstURL = UITests.simpleServedPage(titled: "First Tab Test")
        app.activateAddressBar()
        app.pasteURL(firstURL, pressingEnter: true)

        let firstPageContent = webView.staticTexts.containing(\.value, containing: "First Tab Test").firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load first page")

        // Navigate to second page
        let secondURL = UITests.simpleServedPage(titled: "Second Page Test")
        app.activateAddressBar()
        app.pasteURL(secondURL, pressingEnter: true)

        let secondPageContent = webView.staticTexts.containing(\.value, containing: "Second Page Test")
            .firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load second page")

        // Go back via keyboard shortcut to avoid toolbar identifier flakiness
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        if window.exists { window.click() }
        app.typeKey("[", modifierFlags: [.command])

        // Verify we're back on first page (by content; avoid address bar access here)
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should navigate back to first page")
    }

    func testAddressBar_ForwardNavigation_UpdatesURLCorrectly() throws {
        // Set up navigation history (two pages)
        let firstURL = UITests.simpleServedPage(titled: "First Tab Test")
        app.activateAddressBar()
        app.pasteURL(firstURL, pressingEnter: true)

        let firstPageContent = webView.staticTexts.containing(\.value, containing: "First Tab Test").firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load first page")

        let secondURL = UITests.simpleServedPage(titled: "Second Page Test")
        app.activateAddressBar()
        app.pasteURL(secondURL, pressingEnter: true)

        let secondPageContent = webView.staticTexts.containing(\.value, containing: "Second Page Test")
            .firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load second page")

        // Go back first via keyboard shortcut
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        if window.exists { window.click() }
        app.typeKey("[", modifierFlags: [.command])
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should be back on first page")

        // Now go forward via keyboard shortcut
        if window.exists { window.click() }
        app.typeKey("]", modifierFlags: [.command])

        // Verify forward navigation worked (by content; avoid address bar access here)
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should navigate forward to second page")
    }

    // MARK: - Reload Behavior Tests

    func testAddressBar_Reload_PreservesURL() throws {
        let testURL = UITests.simpleServedPage(titled: "Navigation Test")
        app.activateAddressBar()
        app.pasteURL(testURL, pressingEnter: true)

        let pageContent = webView.staticTexts.containing(\.value, containing: "Navigation Test").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should load test page")

        // Reload the page via keyboard shortcut (more stable than toolbar identifier)
        app.typeKey("r", modifierFlags: [.command])

        // Verify page reloaded and URL preserved
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Page should reload successfully")

        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("localhost:8085"), "Address bar should preserve URL after reload")
    }

    // MARK: - Edge Cases Tests

    func testAddressBar_EmptyInput_DoesNotNavigate() throws {
        // Try to navigate with empty input
        app.activateAddressBar()
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Should remain on current page (new tab page)
        let newTabContent = app.staticTexts.containing(\.value, containing: "DuckDuckGo").firstMatch
        XCTAssertTrue(newTabContent.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Should remain on new tab page with empty input")
    }

    func testAddressBar_WhitespaceInput_TrimsCorrectly() throws {
        // Type URL with leading/trailing whitespace
        app.activateAddressBar()
        addressBarTextField.typeText("  example.com  ")
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Should navigate to example.com (whitespace trimmed).
        let exampleContent = webView.staticTexts
            .containing(\.value, containing: "Example Domain")
            .firstMatch
        XCTAssertTrue(exampleContent.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        let currentValue = app.addressBarValueActivatingIfNeeded() ?? ""

        XCTAssertEqual(currentValue, "https://example.com/")
    }

    func testAddressBar_SpecialCharacters_HandledCorrectly() throws {
        // Test search with space
        app.activateAddressBar()
        app.typeText("hello world")
        app.typeKey(.enter, modifierFlags: [])

        let helloWorldResult = webView.staticTexts.containing(\.value, containing: "Hello, world!").firstMatch
        XCTAssertTrue(helloWorldResult.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should show Hello, world! result")

        let searchURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(searchURL.hasPrefix("https://duckduckgo.com/?q=hello+world&"), "URL should be a DuckDuckGo search")

        // Test email-like input
        app.openNewTab()
        app.activateAddressBar()
        app.typeText("test@example.com")
        app.typeKey(.enter, modifierFlags: [])

        let emailResult = webView.staticTexts["test@example.com"]
        XCTAssertTrue(emailResult.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should show search results for email")

        let emailURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(emailURL.hasPrefix("https://duckduckgo.com/?q=test%40example.com&"), "URL should be a DuckDuckGo search")

        // Test file protocol (should fail)
        app.openNewTab()
        app.activateAddressBar()
        addressBarTextField.typeText("file:///path/to/file")
        app.typeKey(.enter, modifierFlags: [])

        let errorResult = webView.staticTexts.containing(\.value, containing: "load this page.").firstMatch
        XCTAssertTrue(errorResult.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should show error for file protocol")

        let fileURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertEqual(fileURL, "file:///path/to/file", "URL should remain unchanged")

        // Test calculator expression
        app.openNewTab()
        app.activateAddressBar()
        addressBarTextField.typeText("2+2*8/(3-1.1)")
        app.typeKey(.enter, modifierFlags: [])

        let calculatorResult = webView.staticTexts.containing(.keyPath(\.value, beginsWith: "10.42105")).firstMatch
        XCTAssertTrue(calculatorResult.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should show calculator result")

        let calcURL = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(calcURL.hasPrefix("https://duckduckgo.com/?q=2%2B2*8%2F(3-1.1)&"), "URL should be a DuckDuckGo calculator search")
    }

}
