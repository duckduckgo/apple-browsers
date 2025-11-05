//
//  AutoconsentUITests.swift
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
import os.log

class AutoconsentUITests: UITestCase {

    private var addressBarTextField: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()

        // Use existing extension method instead of setupSingleWindow()
        app.enforceSingleWindow()

        // Use extension property instead of manual reference
        addressBarTextField = app.addressBar
        XCTAssertTrue(addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

    }

    // MARK: - Cookie Consent Management Tests

    func testAutoconsent_PrivacyTestPages_ManagesCookieConsent() throws {
        // Navigate to DuckDuckGo's privacy test pages for autoconsent
        let testURL = URL(string: "http://privacy-test-pages.site/features/autoconsent/")!
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for autoconsent test page to load with specific content
        let webView = app.webViews.firstMatch
        let autoconsentPageContent = webView.staticTexts.containing(\.value, containing: "automatic consent popup clicking").firstMatch
        XCTAssertTrue(autoconsentPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Autoconsent test page should load with 'automatic consent popup clicking' text")

        // Verify autoconsent automatically clicked the first button - should show "I was clicked!"
        let clickedButton = webView.buttons.containing(\.title, containing: "I was clicked!").firstMatch
        XCTAssertTrue(clickedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Autoconsent should have automatically clicked the first button, changing it to 'I was clicked!'")

        // Check privacy dashboard for autoconsent status
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available")

        privacyButton.click()

        // Wait for privacy dashboard to open
        let privacyDashboard = app.popovers.firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Look for "Cookies Managed" in the privacy dashboard (for button clicking test)
        let cookiesManagedInfo = privacyDashboard.groups.containing(.button, identifier: "Cookies Managed").firstMatch
        XCTAssertTrue(cookiesManagedInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show 'Cookies Managed' for autoconsent button clicking")

        // Close privacy dashboard
        app.typeKey(.escape, modifierFlags: [])
    }

    func testAutoconsent_CookieBannerHiding_BannersAreHidden() throws {
        // Navigate to test page with cookie banner
        let bannerTestURL = URL(string: "http://privacy-test-pages.site/features/autoconsent/banner.html")!
        addressBarTextField.pasteURL(bannerTestURL, pressingEnter: true)

        // Wait for banner test page to load with specific test content
        let webView = app.webViews.firstMatch
        let bannerTestContent = webView.staticTexts.containing(\.value, containing: "Tests for cosmetic hiding of cookie banners").firstMatch
        XCTAssertTrue(bannerTestContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Banner test page should load with 'Tests for cosmetic hiding of cookie banners' text")

        // Check that banner content is hidden by autoconsent (entire banner should be gone)
        let bannerContent = webView.staticTexts.containing(\.value, containing: "This is a fake consent banner without a reject button").firstMatch
        XCTAssertFalse(bannerContent.exists, "Banner content should be hidden by autoconsent cosmetic filtering")

        let preHiddenElement = webView.staticTexts.containing(\.value, containing: "This should be pre-hidden").firstMatch
        XCTAssertFalse(preHiddenElement.exists, "Pre-hidden element should be hidden by autoconsent cosmetic filtering")

        // Check privacy dashboard shows cookies are managed
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        XCTAssertTrue(privacyButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy button should be available")

        privacyButton.click()

        let privacyDashboard = app.popovers.firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Verify autoconsent is working by checking for "Cookies Managed" status
        let cookiePopupHiddenInfo = privacyDashboard.groups.containing(.button, identifier: "Cookies Managed").firstMatch
        XCTAssertTrue(cookiePopupHiddenInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show 'Cookies Managed' indicating autoconsent is active")

        app.typeKey(.escape, modifierFlags: [])
    }

    func testAutoconsent_MultiplePages_WorksConsistently() throws {
        let webView = app.webViews.firstMatch

        // Page 1: autoclick flow
        app.activateAddressBar()
        addressBarTextField.pasteURL(URL(string: "http://privacy-test-pages.site/features/autoconsent/")!, pressingEnter: true)
        let page1Content = webView.staticTexts.containing(\.value, containing: "Tests for automatic consent popup clicking")
            .firstMatch
        XCTAssertTrue(page1Content.waitForExistence(timeout: UITests.Timeouts.navigation))
        let clickedButton1 = webView.buttons.containing(\.title, containing: "I was clicked!")
            .firstMatch
        XCTAssertTrue(clickedButton1.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Page 2: banner hiding flow
        app.activateAddressBar()
        addressBarTextField.pasteURL(URL(string: "http://privacy-test-pages.site/features/autoconsent/banner.html")!, pressingEnter: true)
        let page2Content = webView.staticTexts.containing(\.value, containing: "Tests for cosmetic hiding of cookie banners")
            .firstMatch
        XCTAssertTrue(page2Content.waitForExistence(timeout: UITests.Timeouts.navigation))
        let bannerText = webView.staticTexts
            .containing(\.value, containing: "This is a fake consent banner without a reject button")
            .firstMatch
        XCTAssertFalse(bannerText.exists)
    }

    func testAutoconsent_PageReload_PersistsSettings() throws {
        // Navigate to autoconsent test page
        let testURL = URL(string: "http://privacy-test-pages.site/features/autoconsent/")!
        addressBarTextField.pasteURL(testURL, pressingEnter: true)

        // Wait for autoconsent test page to load
        let webView = app.webViews.firstMatch
        let autoconsentContent = webView.staticTexts.containing(\.value, containing: "Tests for automatic consent popup clicking")
            .firstMatch
        XCTAssertTrue(autoconsentContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Initial autoconsent page should load with consent popup text")

        // Reload the page
        app.typeKey("r", modifierFlags: [.command])

        // Wait for reload and verify autoclick persists
        XCTAssertTrue(autoconsentContent.waitForExistence(timeout: UITests.Timeouts.navigation))
        let clickedButton = webView.buttons.containing(\.title, containing: "I was clicked!")
            .firstMatch
        XCTAssertTrue(clickedButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Verify dashboard shows cookies managed
        let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
        privacyButton.click()

        // Wait for privacy dashboard to open
        let privacyDashboard = app.popovers.firstMatch
        XCTAssertTrue(privacyDashboard.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should open")

        // Look for "Cookies Managed" in the privacy dashboard (for button clicking test)
        let cookiesManagedInfo = privacyDashboard.groups.containing(.button, identifier: "Cookies Managed").firstMatch
        XCTAssertTrue(cookiesManagedInfo.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Privacy dashboard should show 'Cookies Managed' for autoconsent button clicking")

        // Close privacy dashboard
        app.typeKey(.escape, modifierFlags: [])
    }

    func testAutoconsent_NavigationBetweenSites_MaintainsProtection() throws {
        // Navigate to first test site
        app.activateAddressBar()
        let firstURL = URL(string: "http://privacy-test-pages.site/features/autoconsent/")!
        addressBarTextField.pasteURL(firstURL, pressingEnter: true)

        let webView = app.webViews.firstMatch
        let firstPageContent = webView.staticTexts.containing(\.value, containing: "Tests for automatic consent popup clicking").firstMatch
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "First page should load with consent popup text")
        // Verify auto-click occurred
        let clickedButton2 = webView.buttons.containing(\.title, containing: "I was clicked!")
            .firstMatch
        XCTAssertTrue(clickedButton2.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Navigate to second test site
        app.activateAddressBar()
        let secondURL = URL(string: "http://privacy-test-pages.site/features/autoconsent/banner.html")!
        addressBarTextField.pasteURL(secondURL, pressingEnter: true)

        let secondPageContent = webView.staticTexts.containing(\.value, containing: "Tests for cosmetic hiding of cookie banners")
            .firstMatch
        XCTAssertTrue(secondPageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Second banner page should load with cosmetic hiding text")
        // Verify banner is hidden
        let bannerText2 = webView.staticTexts
            .containing(\.value, containing: "This is a fake consent banner without a reject button")
            .firstMatch
        XCTAssertFalse(bannerText2.exists)

        // Go back to first site
        let backButton = app.buttons.matching(identifier: "NavigationBarViewController.BackButton").firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Back button should be available")
        XCTAssertTrue(backButton.isEnabled, "Back button should be enabled")

        backButton.click()

        // Wait for navigation back and re-verify auto-click result
        XCTAssertTrue(firstPageContent.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        XCTAssertTrue(clickedButton2.waitForExistence(timeout: UITests.Timeouts.elementExistence))

    }
}
