//
//  SearchNonexistentDomainUITests.swift
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

class SearchNonexistentDomainUITests: UITestCase {

    private var webView: XCUIElement!
    private var addressBarTextField: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false
        app = XCUIApplication.setUp()

        // Use existing extension method instead of duplicated helper
        app.enforceSingleWindow()

        // Use extension property instead of creating own reference
        addressBarTextField = app.addressBar
        webView = app.webViews.firstMatch
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Note: On new tab page, address bar is already activated - no Cmd+L needed
    }

    override func tearDown() {
        webView = nil
        addressBarTextField = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Test Cases

    func testWhenInvalidTLDEntered_RedirectsToSearch() throws {
        // Test browser redirects invalid TLD to search (matches integration test behavior)
        let invalidDomain = "testsite.invalidtld"

        // Type invalid domain
        addressBarTextField.typeText(invalidDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - invalid TLD should trigger search redirect
        let searchContent = webView.staticTexts.containing(\.value, containing: invalidDomain).firstMatch
        XCTAssertTrue(searchContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Search results should contain the invalid domain")

        // Verify the URL changed to a search URL by checking address bar after navigation
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "Should redirect to DuckDuckGo search page")
        XCTAssertTrue(addressBarValue.contains(invalidDomain), "Search URL should contain the original search term")
    }

    func testWhenTypoInDomainEntered_RedirectsToSearch() throws {
        // Test browser redirects invalid TLD to search (matches integration test: .coma is invalid TLD)
        let typoedDomain = "google.coma"
        addressBarTextField.typeText(typoedDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - invalid TLD should trigger search redirect
        let searchContent = webView.staticTexts.containing(\.value, containing: typoedDomain).firstMatch
        XCTAssertTrue(searchContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Search results should contain the invalid domain")

        // Verify the URL changed to a search URL by checking address bar after navigation
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "Should redirect to DuckDuckGo search page")
        XCTAssertTrue(addressBarValue.contains(typoedDomain), "Search URL should contain the original search term")
    }

    func testWhenRandomStringEntered_RedirectsToSearch() throws {
        // Test browser redirects random string input to search (matches integration test behavior)
        let randomString = "thisisnotadomainname"
        addressBarTextField.typeText(randomString)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - should load DuckDuckGo search page

        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Web view should load search results page")

        // Verify the URL changed to a search URL by checking address bar after navigation
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "Should redirect to DuckDuckGo search page")
        XCTAssertTrue(addressBarValue.contains(randomString), "Search URL should contain the original search term")
    }

    func testWhenInvalidDomainWithCorrectTLDEntered_ShowsErrorWithoutSearchRedirect() throws {
        // Test browser handles misspelled domain (.com TLD = valid, so should show error page or suggestions, not redirect to search)
        let misspelledSite = "facebok.nonexistent.invalid.domain.com"
        addressBarTextField.typeText(misspelledSite)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for browser handling - look for an error/suggestions indicator in page content

        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Web view should load (error page or actual page)")

        // Suggestions or error page text (robust predicate)
        let suggestionOrErrorText = webView.staticTexts
            .containing(\.value, containing: "could not be found")
            .firstMatch
        XCTAssertTrue(suggestionOrErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Should show suggestions or an error page for misspelled popular site")

        // Address bar remains accessible and contains something
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertEqual(addressBarValue, "http://facebok.nonexistent.invalid.domain.com/")
    }

    func testWhenInvalidDomainRedirected_AddressBarHistoryRecordsSearchURL() throws {
        // Test browser history functionality after invalid domain search redirect
        let invalidDomain = "nonexistent.invalid"
        addressBarTextField.typeText(invalidDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - invalid TLD should trigger search redirect
        let searchContent = webView.staticTexts.containing(\.value, containing: invalidDomain).firstMatch
        XCTAssertTrue(searchContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Search results should contain the invalid domain")

        // Verify history was recorded - address bar should contain search URL
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "History should record the search redirect")
        XCTAssertTrue(addressBarValue.contains(invalidDomain), "Search URL should contain the original search term")
    }

    func testWhenValidDomainEntered_NavigatesWithoutSearchRedirect() throws {
        // Test navigation to a valid domain
        let validDomain = "example.com"
        addressBarTextField.typeText(validDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for navigation to complete by checking for page content
        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        let pageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should navigate to example.com and show page content")

        // Verify browser navigated and remains functional - address bar should still be accessible
        let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertEqual(addressBarValue, "https://example.com/")
    }

    func testWhenHttpSingleSlashEntered_NormalizesToDoubleSlash() throws {
        // http:/ should normalize to http:// prior to navigation
        addressBarTextField.typeText("http:/localhost:8085")
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        let value = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(value.contains("http://localhost:8085"), "Scheme should be normalized to http:// for single-slash input")
    }

    func testWhenLocalhostWithoutSchemeEntered_NavigatesSuccessfully() throws {
        // Typing localhost (no scheme) should navigate, not redirect to search
        addressBarTextField.typeText("localhost")
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        let value = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(value.contains("localhost"))
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testWhenLocalhostWithPortEntered_NavigatesSuccessfully() throws {
        // Typing localhost with port (no scheme) should navigate to local server
        addressBarTextField.typeText("localhost:8085")
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(webView.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        let value = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(value.contains("localhost:8085"))
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testWhenLocalServerURLEntered_LoadsContent() throws {
        // Full local server URL should load normally
        let testContent = "Local Server Test Content"
        let url = URL.testsServer.appendingTestParameters(data: testContent.utf8data)
        addressBarTextField.pasteURL(url, pressingEnter: true)

        let serverContent = webView.staticTexts.containing(\.value, containing: testContent).firstMatch
        XCTAssertTrue(serverContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Should show test content from local server")

        let value = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertTrue(value.contains("localhost"))
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testWhenInvalidDomainWithHTTPEntered_ShowsErrorWithoutSearchRedirect() throws {
        // With scheme and invalid TLD, browser should not redirect to search; expect error page/suggestions
        let invalidURL = URL(string: "http://nonexistent.invalidtld")!
        addressBarTextField.pasteURL(invalidURL, pressingEnter: true)

        // Robust error/suggestion predicate
        let suggestionOrErrorText = webView.staticTexts
            .containing(\.value, containing: "could not be found")
            .firstMatch
        XCTAssertTrue(suggestionOrErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let value = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testWhenInvalidDomainWithHTTPSEntered_ShowsErrorWithoutSearchRedirect() throws {
        // With https and invalid TLD, should not redirect to search; expect error page/suggestions
        let invalidURL = URL(string: "https://nonexistent.invalidtld")!
        addressBarTextField.pasteURL(invalidURL, pressingEnter: true)

        let suggestionOrErrorText = webView.staticTexts
            .containing(\.value, containing: "could not be found")
            .firstMatch
        XCTAssertTrue(suggestionOrErrorText.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let value = app.addressBarValueActivatingIfNeeded() ?? ""
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

}
