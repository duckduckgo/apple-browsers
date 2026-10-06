//
//  BookmarkSortTests.swift
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

class BookmarkSortTests: UITestCase {

    private enum AccessibilityIdentifiers {
        static let resetBookmarksMenuItem = "MainMenu.resetBookmarks"
        static let sortBookmarksButtonPanel = "BookmarkListViewController.sortBookmarksButton"
        static let sortBookmarksButtonManager = "BookmarkManagementDetailViewController.sortItemsButton"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        app.resetBookmarks()
        app.enforceSingleWindow()
    }

    func testWhenNoBookmarksThenSortIsDisabledOnThePanel() {
        app.openBookmarksPanel()

        let bookmarksPanelPopover = app.popovers.firstMatch
        let sortBookmarksButton = bookmarksPanelPopover.buttons[AccessibilityIdentifiers.sortBookmarksButtonPanel]
        XCTAssertFalse(sortBookmarksButton.isEnabled)
    }

    func testWhenNoBookmarksThenSortIsDisabledOnTheManager() {
        app.openBookmarksManager()

        let sortBookmarksButton = app.buttons[AccessibilityIdentifiers.sortBookmarksButtonManager]
        XCTAssertFalse(sortBookmarksButton.isEnabled)
    }

    func testWhenChangingSortingInThePanelIsReflectedInTheManager() {
        addBookmark(pageTitle: "Bookmark #1")
        app.dismissBookmarksBarPopover()
        app.openBookmarksPanel()
        selectSortByName(mode: .panel)
        app.closeBookmarksPanel()
        app.openBookmarksManager()

        app.buttons[AccessibilityIdentifiers.sortBookmarksButtonManager].clickAfterExistenceTestSucceeds()

        /// If the ascending and descending sort options are enabled, means that the sort in the panel was reflected here.
        XCTAssertTrue(app.menuItems["Ascending"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(app.menuItems["Ascending"].isEnabled)
        XCTAssertTrue(app.menuItems["Descending"].isEnabled)
    }

    func testWhenChangingSortingInTheManagerIsReflectedInThePanel() {
        addBookmark(pageTitle: "Bookmark #1")
        app.dismissBookmarksBarPopover()
        app.openBookmarksManager()
        selectSortByName(mode: .manager)
        app.closeCurrentTab()
        app.openBookmarksPanel()

        let bookmarksPanelPopover = app.popovers.firstMatch
        bookmarksPanelPopover.buttons[AccessibilityIdentifiers.sortBookmarksButtonPanel].clickAfterExistenceTestSucceeds()

        XCTAssertTrue(bookmarksPanelPopover.menuItems["Ascending"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(bookmarksPanelPopover.menuItems["Ascending"].isEnabled)
        XCTAssertTrue(bookmarksPanelPopover.menuItems["Descending"].isEnabled)
    }

    func testManualSortWorksAsExpectedOnBookmarksPanel() {
        ["Bookmark #2", "Bookmark #3", "Bookmark #1"].forEach {
            addBookmark(pageTitle: $0)
            app.openNewTab()
        }

        app.openBookmarksPanel()
        app.verifyBookmarkOrder(expectedOrder: ["Bookmark #2", "Bookmark #3", "Bookmark #1"], mode: .panel)
    }

    func testManualSortWorksAsExpectedOnBookmarksManager() {
        ["Bookmark #2", "Bookmark #3", "Bookmark #1"].forEach {
            addBookmark(pageTitle: $0)
            app.openNewTab()
        }

        app.openBookmarksManager()
        app.verifyBookmarkOrder(expectedOrder: ["Bookmark #2", "Bookmark #3", "Bookmark #1"], mode: .manager)
    }

    func testNameAscendingSortWorksAsExpectedOnBookmarksPanel() {
        ["Bookmark #2", "Bookmark #3", "Bookmark #1"].forEach {
            addBookmark(pageTitle: $0)
            app.openNewTab()
        }

        app.openBookmarksPanel()
        selectSortByName(mode: .panel)
        app.verifyBookmarkOrder(expectedOrder: ["Bookmark #1", "Bookmark #2", "Bookmark #3"], mode: .panel)
    }

    func testNameAscendingSortWorksAsExpectedOnBookmarksManager() {
        ["Bookmark #2", "Bookmark #3", "Bookmark #1"].forEach {
            addBookmark(pageTitle: $0)
            app.openNewTab()
        }

        app.openBookmarksManager()
        selectSortByName(mode: .manager)
        app.verifyBookmarkOrder(expectedOrder: ["Bookmark #1", "Bookmark #2", "Bookmark #3"], mode: .manager)
    }

    func testNameDescendingSortWorksAsExpectedOnBookmarksPanel() {
        ["Bookmark #2", "Bookmark #3", "Bookmark #1"].forEach {
            addBookmark(pageTitle: $0)
            app.openNewTab()
        }

        app.openBookmarksPanel()
        selectSortByName(mode: .panel, descending: true)
        app.verifyBookmarkOrder(expectedOrder: ["Bookmark #3", "Bookmark #2", "Bookmark #1"], mode: .panel)
    }

    func testNameDescendingSortWorksAsExpectedOnBookmarksManager() {
        ["Bookmark #2", "Bookmark #3", "Bookmark #1"].forEach {
            addBookmark(pageTitle: $0)
            app.openNewTab()
        }

        app.openBookmarksManager()
        selectSortByName(mode: .manager, descending: true)
        app.verifyBookmarkOrder(expectedOrder: ["Bookmark #3", "Bookmark #2", "Bookmark #1"], mode: .manager)
    }

    func testThatSortIsPersistedThroughBrowserRestarts() {
        addBookmark(pageTitle: "Bookmark #1")
        app.dismissBookmarksBarPopover()
        app.openBookmarksPanel()
        selectSortByName(mode: .panel)

        app.restart(forceTerminate: true)
        app.enforceSingleWindow()

        // Wait for new application to start
        XCTAssertTrue(app.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        app.dismissBookmarksBarPopover()
        app.openBookmarksPanel()

        let sortBookmarksPanelButton = app.popovers.firstMatch.buttons[AccessibilityIdentifiers.sortBookmarksButtonPanel]
        sortBookmarksPanelButton.clickAfterExistenceTestSucceeds()

        let sortByNameManual = app.menuItems["Manual"]
        let sortByNameMenuItem = app.menuItems["Name"]
        let sortByNameAscendingMenuItem = app.menuItems["Ascending"]
        let sortByNameDescendingMenuItem = app.menuItems["Descending"]

        XCTAssertTrue(sortByNameManual.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(sortByNameManual.isEnabled)
        XCTAssertTrue(sortByNameMenuItem.isEnabled)
        XCTAssertTrue(sortByNameAscendingMenuItem.isEnabled)
        XCTAssertTrue(sortByNameDescendingMenuItem.isEnabled)
    }

    // MARK: - Utilities

    private func tapPanelSortButton() {
        let bookmarksPanelPopover = app.popovers.firstMatch
        let sortBookmarksButton = bookmarksPanelPopover.buttons[AccessibilityIdentifiers.sortBookmarksButtonPanel]
        sortBookmarksButton.clickAfterExistenceTestSucceeds()
    }

    private func selectSortByName(mode: BookmarkMode, descending: Bool = false) {
        if mode == .panel {
            let bookmarksPanelPopover = app.popovers.firstMatch
            let sortBookmarksButton = bookmarksPanelPopover.buttons[AccessibilityIdentifiers.sortBookmarksButtonPanel]
            sortBookmarksButton.clickAfterExistenceTestSucceeds()
            bookmarksPanelPopover.menuItems["Name"].clickAfterExistenceTestSucceeds()

            if descending {
                sortBookmarksButton.clickAfterExistenceTestSucceeds()
                bookmarksPanelPopover.menuItems["Descending"].clickAfterExistenceTestSucceeds()
            }
        } else {
            let sortBookmarksButton = app.buttons[AccessibilityIdentifiers.sortBookmarksButtonManager]
            sortBookmarksButton.clickAfterExistenceTestSucceeds()
            app.menuItems["Name"].clickAfterExistenceTestSucceeds()

            if descending {
                sortBookmarksButton.clickAfterExistenceTestSucceeds()
                app.menuItems["Descending"].clickAfterExistenceTestSucceeds()
                /// Here we hover over the sort button, because if we stay where the 'Descending' was selected
                /// the label of the bookmark being hovered is different because it shows the URL.
                sortBookmarksButton.hover()
            }
        }
    }

    private func addBookmark(pageTitle: String, in folder: String? = nil) {
        let urlForBookmarksBar = UITests.simpleServedPage(titled: pageTitle)
        app.openSiteToBookmark(url: urlForBookmarksBar,
                               pageTitle: pageTitle,
                               bookmarkingViaDialog: true,
                               escapingDialog: true,
                               folderName: folder)
    }
}
