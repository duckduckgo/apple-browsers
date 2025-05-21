//
//  BookmarksBarVisibilityTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

class BookmarksBarVisibilityTests: UITestCase {
    private var app: XCUIApplication!
    private var pageTitle: String!
    private var urlForBookmarksBar: URL!
    private let titleStringLength = 12

    private var addressBarTextField: XCUIElement!
    private var bookmarksBarCollectionView: XCUIElement!
    private var defaultBookmarkDialogButton: XCUIElement!
    private var resetBookMarksMenuItem: XCUIElement!
    private var skipOnboardingMenuItem: XCUIElement!
    private var bookmarksBarPromptPopover: XCUIElement!

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        pageTitle = UITests.randomPageTitle(length: titleStringLength)
        urlForBookmarksBar = UITests.simpleServedPage(titled: pageTitle)

        addressBarTextField = app.textFields["AddressBarViewController.addressBarTextField"]
        bookmarksBarCollectionView = app.collectionViews["BookmarksBarViewController.bookmarksBarCollectionView"]
        defaultBookmarkDialogButton = app.buttons["BookmarkDialogButtonsView.defaultButton"]
        resetBookMarksMenuItem = app.menuItems["MainMenu.resetBookmarks"]
        skipOnboardingMenuItem = app.menuItems["MainMenu.skipOnboarding"]
        bookmarksBarPromptPopover = app.popovers.containing(NSPredicate(format: "title == %@", "Show Bookmarks Bar?")).element

        app.launch()
        resetBookmarks()
        skipOnboarding()
        app.typeKey("w", modifierFlags: [.command, .option, .shift]) // Close all windows
        app.typeKey("n", modifierFlags: .command) // Open new window
    }

    func test_bookmarksBar_remainsVisibleAfterAcceptingPrompt() throws {
        // Visit a site
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The Address Bar text field did not exist when it was expected."
        )
        addressBarTextField.typeURL(urlForBookmarksBar)

        // Wait for the page to load
        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )

        // Add bookmark
        app.typeKey("d", modifierFlags: .command)

        // Verify bookmark dialog appears and add the bookmark
        XCTAssertTrue(
            defaultBookmarkDialogButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmark dialog button didn't appear in a reasonable timeframe."
        )
        defaultBookmarkDialogButton.click()

        // Verify bookmarks bar is visible
        XCTAssertTrue(
            bookmarksBarCollectionView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar should get visible when first bookmark is added."
        )

        // Verify bookmarks bar prompt popover appears
        XCTAssertTrue(
            bookmarksBarPromptPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar prompt popover didn't appear after adding bookmark."
        )

        // Click the 'Show' button in the popover
        let showButton = bookmarksBarPromptPopover.buttons["Show"]
        XCTAssertTrue(showButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Show button did not appear in the bookmarks bar prompt popover.")
        showButton.click()

        // Verify bookmarks bar remains visible after closing popover
        XCTAssertTrue(
            bookmarksBarCollectionView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar should remain visible after closing prompt popover."
        )

        // Open a new tab
        app.typeKey("t", modifierFlags: .command)

        // Verify bookmarks bar is shown in the new tab
        XCTAssertTrue(
            bookmarksBarCollectionView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar should be hidden in new tab after dismissing prompt popover."
        )
    }

    func test_bookmarksBar_hiddenAfterRejectingPrompt() throws {
        // Visit a site
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The Address Bar text field did not exist when it was expected."
        )
        addressBarTextField.typeURL(urlForBookmarksBar)

        // Wait for the page to load
        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )

        // Add bookmark
        app.typeKey("d", modifierFlags: .command)

        // Verify bookmark dialog appears and add the bookmark
        XCTAssertTrue(
            defaultBookmarkDialogButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmark dialog button didn't appear in a reasonable timeframe."
        )
        defaultBookmarkDialogButton.click()

        // Verify bookmarks bar is visible
        XCTAssertTrue(
            bookmarksBarCollectionView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar should get visible when first bookmark is added."
        )

        // Verify bookmarks bar prompt popover appears
        XCTAssertTrue(
            bookmarksBarPromptPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar prompt popover didn't appear after adding bookmark."
        )

        // Click the 'Hide' button in the popover
        let hideButton = bookmarksBarPromptPopover.buttons["Hide"]
        XCTAssertTrue(hideButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Hide button did not appear in the bookmarks bar prompt popover.")
        hideButton.click()

        // Verify bookmarks bar is hidden after closing popover
        XCTAssertFalse(
            bookmarksBarCollectionView.exists,
            "Bookmarks bar should be hidden after rejecting prompt popover."
        )
    }

    func test_bookmarksBar_hiddenAfterDismissingPrompt() throws {
        // Visit a site
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The Address Bar text field did not exist when it was expected."
        )
        addressBarTextField.typeURL(urlForBookmarksBar)

        // Wait for the page to load
        XCTAssertTrue(
            app.windows.webViews[pageTitle].waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Visited site didn't load with the expected title in a reasonable timeframe."
        )

        // Add bookmark
        app.typeKey("d", modifierFlags: .command)

        // Verify bookmark dialog appears and add the bookmark
        XCTAssertTrue(
            defaultBookmarkDialogButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmark dialog button didn't appear in a reasonable timeframe."
        )
        defaultBookmarkDialogButton.click()

        // Verify bookmarks bar is visible
        XCTAssertTrue(
            bookmarksBarCollectionView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar should get visible when first bookmark is added."
        )

        // Verify bookmarks bar prompt popover appears
        XCTAssertTrue(
            bookmarksBarPromptPopover.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Bookmarks bar prompt popover didn't appear after adding bookmark."
        )

        // Click outside the popover to dismiss it
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        // Open a new tab
        app.typeKey("t", modifierFlags: .command)

        // Verify bookmarks bar is hidden in the new tab
        XCTAssertFalse(
            bookmarksBarCollectionView.exists,
            "Bookmarks bar should be hidden in new tab after dismissing prompt popover."
        )
    }

    private func resetBookmarks() {
        XCTAssertTrue(
            resetBookMarksMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Reset bookmarks menu item didn't become available in a reasonable timeframe."
        )
        resetBookMarksMenuItem.click()
    }

    private func skipOnboarding() {
        XCTAssertTrue(
            skipOnboardingMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Skip onboarding menu item didn't become available in a reasonable timeframe."
        )
        skipOnboardingMenuItem.click()
    }
}
