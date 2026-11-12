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

    override var additionalLaunchEnvironment: [String: String] {
        // Avoid XCTest's repeated animation-idle timeouts in bookmark workflows.
        [
            "UITEST_DISABLE_ANIMATIONS": "1",
            "UITEST_TEMPORARY_BOOKMARKS_STORE": "1",
        ]
    }

    override var launchesAppInSetUp: Bool {
        false
    }

    func testWhenPageIsBookmarkedThenItCanBeOpenedAndDeleted() throws {
        let site = try localWebsite()
        app.launch()
        let bookmark = app.tables["Bookmarks.List"].cells["Bookmarks.Item"].firstMatch

        XCTContext.runActivity(named: "Bookmark the test page") { _ in
            site.open(.first, in: app)
            app.openBrowsingMenuItem("Browser.Menu.AddBookmark")
        }

        XCTContext.runActivity(named: "Open the bookmark from autocomplete and refresh it") { _ in
            app.openNewTab()
            app.enterSearchText("first")
            app.openAutocompleteSuggestion(
                withIdentifierPrefix: "Autocomplete.Suggestions.ListItem.Bookmark-")
            app.assertPageContains(LocalUITestWebsite.Page.first.title)
            app.webViews.firstMatch.swipeDown()
            app.assertPageContains(LocalUITestWebsite.Page.first.title)
        }

        XCTContext.runActivity(named: "Open the bookmark from Bookmarks") { _ in
            app.openBookmarks()
            bookmark.tapWhenHittable(in: app)
            app.assertPageContains(LocalUITestWebsite.Page.first.title)
        }

        XCTContext.runActivity(named: "Delete the bookmark") { _ in
            app.openBookmarks()
            app.deleteBookmarkFromEditor(bookmark)
            app.assertBookmarksEmpty()
        }
    }

    func testWhenBookmarkIsMovedThroughNestedFoldersThenItCanBeDeletedWithItsFolders() throws {
        let site = try localWebsite()
        app.launch()
        let firstFolderName = "Test Folder"
        let secondFolderName = "Test Folder 2"
        let bookmarksList = app.tables["Bookmarks.List"]
        let bookmark = bookmarksList.cells["Bookmarks.Item"].firstMatch
        let folder = bookmarksList.cells["Bookmarks.Folder"].firstMatch

        XCTContext.runActivity(named: "Bookmark the test page") { _ in
            site.open(.first, in: app)
            app.openBrowsingMenuItem("Browser.Menu.AddBookmark")
            app.openBookmarks()
        }

        XCTContext.runActivity(named: "Move the bookmark into the first folder") { _ in
            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)
            bookmark.tapWhenHittable(in: app)
            app.createBookmarkFolder(named: firstFolderName)
            app.saveBookmarkEditor()
            XCTAssertFalse(
                bookmark.exists,
                "Bookmark remained at the root after being moved into the first folder.")
            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)

            XCTAssertTrue(
                app.staticTexts[firstFolderName].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "First folder did not appear in Bookmarks.")
            folder.tapWhenHittable(in: app)
        }

        XCTContext.runActivity(named: "Move the bookmark into the nested folder") { _ in
            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)
            bookmark.tapWhenHittable(in: app)
            app.createBookmarkFolder(named: secondFolderName)
            app.saveBookmarkEditor()
            XCTAssertFalse(
                bookmark.exists,
                "Bookmark remained in the first folder after being moved into the nested folder.")
            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)

            XCTAssertTrue(
                app.staticTexts[secondFolderName].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Nested folder did not appear in Bookmarks.")
            folder.tapWhenHittable(in: app)
        }

        XCTContext.runActivity(named: "Delete the bookmark from the nested folder") { _ in
            app.deleteBookmarkFromEditor(bookmark)
            XCTAssertTrue(
                bookmark.wait(
                    for: NSPredicate(format: "exists == false"),
                    timeout: UITestTimeouts.elementExistence),
                "Deleted bookmark is still present in the nested folder.")
            app.closeBookmarksAfterEditing()
        }

        XCTContext.runActivity(named: "Delete the non-empty folder hierarchy") { _ in
            app.openBookmarks()
            app.deleteBookmarkFolder(folder, expectedChildCount: 1)
            app.assertBookmarksEmpty()
        }
    }

    func testWhenAllTabsAreBookmarkedThenTheirFolderCanBeDeleted() throws {
        let site = try localWebsite()
        app.launch()
        let folderName = "Examples"
        let bookmarksList = app.tables["Bookmarks.List"]
        let bookmarks = bookmarksList.cells.matching(identifier: "Bookmarks.Item")
        let folder = bookmarksList.cells["Bookmarks.Folder"].firstMatch

        XCTContext.runActivity(named: "Create five tabs with four bookmarkable pages") { _ in
            for index in 0..<4 {
                site.open(.bookmark(index), in: app)
                app.openNewTab()
            }
            app.buttons["UnifiedToggleInput.Button.Dismiss"].tapWhenHittable(in: app)
        }

        XCTContext.runActivity(named: "Bookmark all open tabs") { _ in
            app.bookmarkAllOpenTabs(expectedTabCount: 5)
            app.openBookmarks()
            app.assertBookmarkCount(4)
        }

        XCTContext.runActivity(named: "Create a folder and move all bookmarks into it") { _ in
            app.createBookmarkFolderAtRoot(named: folderName)
            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)

            for remainingCount in stride(from: 3, through: 0, by: -1) {
                bookmarks.firstMatch.tapWhenHittable(in: app)
                let destination = app.tables["Bookmarks.Editor.List"]
                    .cells.matching(identifier: "Bookmarks.Editor.Folder")
                    .containing(.staticText, identifier: folderName)
                    .firstMatch
                app.tables["Bookmarks.Editor.List"].swipeUpToReveal(destination)
                destination.tapWhenHittable(in: app)
                app.saveBookmarkEditor()
                app.assertBookmarkCount(remainingCount)
            }

            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)
            XCTAssertTrue(
                folder.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Created folder is missing after moving the bookmarks.")
        }

        XCTContext.runActivity(named: "Delete the folder and its bookmarks") { _ in
            app.deleteBookmarkFolder(folder, expectedChildCount: 4)
            app.assertBookmarksEmpty()
        }
    }

    func testWhenFolderIsRemovedFromBookmarksEditThenItCanBeDeleted() {
        let folderName = "Removable Folder"
        app.launchEnvironment["UITEST_BOOKMARKS_FOLDER_WITH_ONE_BOOKMARK"] = folderName
        app.launch()
        app.openBookmarks()
        let folder = app.tables["Bookmarks.List"].cells.matching(identifier: "Bookmarks.Folder")
            .containing(.staticText, identifier: folderName).firstMatch
        app.assertBookmarkCount(0)

        XCTContext.runActivity(named: "Remove the folder from Bookmarks Edit") { _ in
            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)
            XCTAssertTrue(folder.waitForExistence(timeout: UITestTimeouts.elementExistence))
            app.buttons["Remove \(folderName)"].tapWhenHittable(in: app)
            app.tables["Bookmarks.List"].buttons["Delete"].tapWhenHittable(in: app)

            let confirmation = app.alerts.firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: UITestTimeouts.elementExistence))
            XCTAssertTrue(confirmation.staticTexts["Delete \(folderName)?"].exists)
            let countText = confirmation.staticTexts.matching(
                NSPredicate(format: "label MATCHES %@", ".*\\b1\\b.*")
            ).firstMatch
            XCTAssertTrue(countText.exists, "Folder deletion warning did not show its one child.")
            app.buttons.matching(identifier: "Bookmarks.Folder.ConfirmDelete").firstMatch.tapWhenHittable(in: app)
            XCTAssertTrue(
                folder.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
                "Removed folder is still present in Bookmarks.")
            app.assertBookmarksEmpty()
        }
    }

    func testWhenTwoTabsAreBookmarkedThenBothAppearInBookmarks() throws {
        let site = try localWebsite()
        app.launch()
        let expectedTitles = [LocalUITestWebsite.Page.first.title, LocalUITestWebsite.Page.second.title]

        XCTContext.runActivity(named: "Create two bookmarkable tabs") { _ in
            site.open(.first, in: app)
            app.openNewTab()
            site.open(.second, in: app)
        }

        XCTContext.runActivity(named: "Bookmark both open tabs") { _ in
            app.bookmarkAllOpenTabs(expectedTabCount: 2)
        }

        XCTContext.runActivity(named: "Verify both bookmarks were added") { _ in
            app.openBookmarks()
            app.assertBookmarkCount(expectedTitles.count)

            let bookmarks = app.tables["Bookmarks.List"].cells.matching(identifier: "Bookmarks.Item")
            for title in expectedTitles {
                let bookmark = bookmarks.containing(.staticText, identifier: title).firstMatch
                XCTAssertTrue(
                    bookmark.waitForExistence(timeout: UITestTimeouts.elementExistence),
                    "Bookmark '\(title)' did not appear.")
            }
        }
    }
}
