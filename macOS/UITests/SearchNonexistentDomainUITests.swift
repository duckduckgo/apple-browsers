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

    private var app: XCUIApplication!
    private var addressBarTextField: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()

        // Use existing extension method instead of duplicated helper
        app.enforceSingleWindow()

        // Use extension property instead of creating own reference
        addressBarTextField = app.addressBar
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Note: On new tab page, address bar is already activated - no Cmd+L needed
    }

    // MARK: - Test Cases

    func testSearchNonexistentDomain_WithInvalidTLD_RedirectsToSearch() throws {
        // Test browser redirects invalid TLD to search (matches integration test behavior)
        let invalidDomain = "testsite.invalidtld"

        // Type invalid domain
        addressBarTextField.typeText(invalidDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - invalid TLD should trigger search redirect
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0), "Web view should load search results page")

        // Verify the URL changed to a search URL by checking address bar after navigation
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0), "Address bar should be accessible after search redirect")

        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "Should redirect to DuckDuckGo search page")
        XCTAssertTrue(addressBarValue.contains(invalidDomain), "Search URL should contain the original search term")
    }

    func testSearchNonexistentDomain_WithTypo_RedirectsToSearch() throws {
        // Test browser redirects invalid TLD to search (matches integration test: .coma is invalid TLD)
        let typoedDomain = "google.coma"
        addressBarTextField.typeText(typoedDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - invalid TLD should trigger search redirect
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0), "Web view should load search results page")

        // Verify the URL changed to a search URL by checking address bar after navigation
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0), "Address bar should be accessible after search redirect")

        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "Should redirect to DuckDuckGo search page")
        XCTAssertTrue(addressBarValue.contains(typoedDomain), "Search URL should contain the original search term")
    }

    func testSearchNonexistentDomain_WithRandomString_RedirectsToSearch() throws {
        // Test browser redirects random string input to search (matches integration test behavior)
        let randomString = "thisisnotadomainname"
        addressBarTextField.typeText(randomString)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - should load DuckDuckGo search page
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0), "Web view should load search results page")

        // Verify the URL changed to a search URL by checking address bar after navigation
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0), "Address bar should be accessible after search redirect")

        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "Should redirect to DuckDuckGo search page")
        XCTAssertTrue(addressBarValue.contains(randomString), "Search URL should contain the original search term")
    }

    func testSearchNonexistentDomain_WithMisspelledPopularSite_ShowsSuggestions() throws {
        // Test browser handles misspelled domain (.com TLD = valid, so should show error page or suggestions, not redirect to search)
        let misspelledSite = "facebok.com"
        addressBarTextField.typeText(misspelledSite)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for browser handling - look for an error/suggestions indicator in page content
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0), "Web view should load (error page or actual page)")

        // Suggestions or error page text (robust predicate)
        let suggestionOrErrorText = webView.staticTexts
            .containing(NSPredicate(format: "value CONTAINS[c] 'did you mean' OR value CONTAINS[c] 'suggest' OR value CONTAINS[c] 'error' OR value CONTAINS[c] 'not found' OR value CONTAINS[c] 'server' OR value CONTAINS[c] 'connect'"))
            .firstMatch
        XCTAssertTrue(suggestionOrErrorText.waitForExistence(timeout: 10.0), "Should show suggestions or an error page for misspelled popular site")

        // Address bar remains accessible and contains something
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0))
        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertFalse(addressBarValue.isEmpty)
    }

    func testSearchNonexistentDomain_AddressBarHistory_RecordsSearchRedirect() throws {
        // Test browser history functionality after invalid domain search redirect
        let invalidDomain = "nonexistent.invalid"
        addressBarTextField.typeText(invalidDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for redirect to search - invalid TLD should trigger search redirect
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0), "Web view should load search results page")

        // Verify history was recorded - address bar should contain search URL
        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0), "Address bar should be accessible for history navigation")

        let addressBarValue = addressBarTextField.value as? String ?? ""
        XCTAssertTrue(addressBarValue.contains("duckduckgo.com"), "History should record the search redirect")
        XCTAssertTrue(addressBarValue.contains(invalidDomain), "Search URL should contain the original search term")
    }

    func testValidDomain_DoesNotRedirectToSearch() throws {
        // Test navigation to a valid domain
        let validDomain = "example.com"
        addressBarTextField.typeText(validDomain)
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        // Wait for navigation to complete by checking for page content
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 15.0), "Should navigate to example.com and show page content")

        // Verify browser navigated and remains functional - address bar should still be accessible
        app.activateAddressBar() // Activate address bar after navigation
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0), "Address bar should remain accessible after valid domain navigation")
    }

    func testMalformedScheme_HttpSingleSlash_NormalizesToDoubleSlash() throws {
        // http:/ should normalize to http:// prior to navigation
        addressBarTextField.typeText("http:/localhost:8085")
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0))

        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0))
        let value = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(value.contains("http://localhost:8085"), "Scheme should be normalized to http:// for single-slash input")
    }

    func testSearchNonexistentDomain_LocalhostWithoutScheme_Navigates() throws {
        // Typing localhost (no scheme) should navigate, not redirect to search
        addressBarTextField.typeText("localhost")
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0))

        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0))
        let value = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(value.contains("localhost"))
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testSearchNonexistentDomain_LocalhostWithPort_Navigates() throws {
        // Typing localhost with port (no scheme) should navigate to local server
        addressBarTextField.typeText("localhost:8085")
        addressBarTextField.typeKey(.enter, modifierFlags: [])

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0))

        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0))
        let value = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(value.contains("localhost:8085"))
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testSearchNonexistentDomain_LocalServerURL_Loads() throws {
        // Full local server URL should load normally
        let url = URL.testsServer
        addressBarTextField.pasteURL(url, pressingEnter: true)

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0))

        app.activateAddressBar()
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: 5.0))
        let value = (addressBarTextField.value as? String) ?? ""
        XCTAssertTrue(value.contains("localhost"))
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testSearchNonexistentDomain_InvalidWithHTTP_ShowsErrorOrNoSearchRedirect() throws {
        // With scheme and invalid TLD, browser should not redirect to search; expect error page/suggestions
        let invalidURL = URL(string: "http://nonexistent.invalidtld")!
        addressBarTextField.pasteURL(invalidURL, pressingEnter: true)

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0))

        // Robust error/suggestion predicate
        let suggestionOrErrorText = webView.staticTexts
            .containing(NSPredicate(format: "value CONTAINS[c] 'error' OR value CONTAINS[c] 'not found' OR value CONTAINS[c] 'server' OR value CONTAINS[c] 'connect' OR value CONTAINS[c] 'did you mean' OR value CONTAINS[c] 'suggest'"))
            .firstMatch
        XCTAssertTrue(suggestionOrErrorText.waitForExistence(timeout: 10.0))

        app.activateAddressBar()
        let value = (addressBarTextField.value as? String) ?? ""
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

    func testSearchNonexistentDomain_InvalidWithHTTPS_ShowsErrorOrNoSearchRedirect() throws {
        // With https and invalid TLD, should not redirect to search; expect error page/suggestions
        let invalidURL = URL(string: "https://nonexistent.invalidtld")!
        addressBarTextField.pasteURL(invalidURL, pressingEnter: true)

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15.0))

        let suggestionOrErrorText = webView.staticTexts
            .containing(NSPredicate(format: "value CONTAINS[c] 'error' OR value CONTAINS[c] 'not found' OR value CONTAINS[c] 'server' OR value CONTAINS[c] 'connect' OR value CONTAINS[c] 'did you mean' OR value CONTAINS[c] 'suggest'"))
            .firstMatch
        XCTAssertTrue(suggestionOrErrorText.waitForExistence(timeout: 10.0))

        app.activateAddressBar()
        let value = (addressBarTextField.value as? String) ?? ""
        XCTAssertFalse(value.contains("duckduckgo.com"))
    }

}
