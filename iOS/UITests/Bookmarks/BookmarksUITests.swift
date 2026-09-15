//
//  BookmarksUITests.swift
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
import UITestingSupport

final class BookmarksUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.resetBookmarks()
    }

    func testWhenPageIsBookmarkedThenItCanBeOpenedAndDeleted() {
        let bookmark = app.tables["Bookmarks.List"].cells["Bookmarks.Item"].firstMatch

        XCTContext.runActivity(named: "Bookmark the test page") { _ in
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.openBrowsingMenuItem("Browser.Menu.AddBookmark")
        }

        XCTContext.runActivity(named: "Open the bookmark from autocomplete and refresh it") { _ in
            app.openNewTab()
            app.enterSearchText("pri")
            app.openAutocompleteSuggestion(
                withIdentifierPrefix: "Autocomplete.Suggestions.ListItem.Bookmark-")
            app.assertPageContains("Privacy Test Pages")
            app.webViews.firstMatch.swipeDown()
            app.assertPageContains("Privacy Test Pages")
        }

        XCTContext.runActivity(named: "Open the bookmark from Bookmarks") { _ in
            app.openBookmarks()
            bookmark.tapWhenHittable()
            app.assertPageContains("Privacy Test Pages")
        }

        XCTContext.runActivity(named: "Delete the bookmark") { _ in
            app.openBookmarks()
            app.deleteBookmark(bookmark)
            app.assertBookmarksEmpty()
        }
    }

    func testWhenBookmarkIsMovedThroughNestedFoldersThenItCanBeDeletedWithItsFolders() {
        let firstFolderName = "Test Folder"
        let secondFolderName = "Test Folder 2"
        let bookmarksList = app.tables["Bookmarks.List"]
        let bookmark = bookmarksList.cells["Bookmarks.Item"].firstMatch
        let folder = bookmarksList.cells["Bookmarks.Folder"].firstMatch

        XCTContext.runActivity(named: "Bookmark the test page") { _ in
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.openBrowsingMenuItem("Browser.Menu.AddBookmark")
            app.openBookmarks()
        }

        XCTContext.runActivity(named: "Move the bookmark into the first folder") { _ in
            app.buttons["Bookmarks.Edit"].tapWhenHittable()
            bookmark.tapWhenHittable()
            app.createBookmarkFolder(named: firstFolderName)
            app.saveBookmarkEditor()
            XCTAssertFalse(
                bookmark.exists,
                "Bookmark remained at the root after being moved into the first folder.")
            app.buttons["Bookmarks.Edit"].tapWhenHittable()

            XCTAssertTrue(
                app.staticTexts[firstFolderName].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "First folder did not appear in Bookmarks.")
            folder.tapWhenHittable()
        }

        XCTContext.runActivity(named: "Move the bookmark into the nested folder") { _ in
            app.buttons["Bookmarks.Edit"].tapWhenHittable()
            bookmark.tapWhenHittable()
            app.createBookmarkFolder(named: secondFolderName)
            app.saveBookmarkEditor()
            XCTAssertFalse(
                bookmark.exists,
                "Bookmark remained in the first folder after being moved into the nested folder.")
            app.buttons["Bookmarks.Edit"].tapWhenHittable()

            XCTAssertTrue(
                app.staticTexts[secondFolderName].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Nested folder did not appear in Bookmarks.")
            folder.tapWhenHittable()
        }

        XCTContext.runActivity(named: "Delete the bookmark from the nested folder") { _ in
            app.deleteBookmark(bookmark)
            XCTAssertTrue(
                bookmark.wait(
                    for: NSPredicate(format: "exists == false"),
                    timeout: UITestTimeouts.elementExistence),
                "Deleted bookmark is still present in the nested folder.")
            app.closeBookmarksAfterEditing()
        }

        XCTContext.runActivity(named: "Delete the non-empty folder hierarchy") { _ in
            app.openBookmarks()
            XCTAssertTrue(
                folder.wait(
                    for: NSPredicate(format: "exists == true AND isHittable == true"),
                    timeout: UITestTimeouts.elementExistence),
                "Folder did not become available for deletion.")
            folder.swipeLeft()
            // UIKit does not expose an identifier for contextual actions. Tap the revealed trailing
            // action relative to the semantically identified folder, then verify its confirmation.
            folder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            app.buttons.matching(identifier: "Bookmarks.Folder.ConfirmDelete").firstMatch.tapWhenHittable()

            app.assertBookmarksEmpty()
        }
    }
}
