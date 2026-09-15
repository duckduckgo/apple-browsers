//
//  XCUIApplication+Bookmarks.swift
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

extension XCUIApplication {

    func openBrowsingMenuItem(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        buttons["Browser.Toolbar.Button.Menu"].tapWhenHittable(file: file, line: line)
        let item = descendants(matching: .any)[identifier]
        let menu = descendants(matching: .any)["Browser.Menu.List"]
        menu.swipeUpToReveal(item, file: file, line: line)
        item.tap()
    }

    func openBookmarks(file: StaticString = #filePath, line: UInt = #line) {
        openBrowsingMenuItem("Browser.Menu.Bookmarks", file: file, line: line)
        XCTAssertTrue(
            tables["Bookmarks.List"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Bookmarks list did not appear.", file: file, line: line)
    }

    func assertBookmarksEmpty(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            descendants(matching: .any)["Bookmarks.EmptyState"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Bookmarks empty state did not appear.", file: file, line: line)
        let bookmarkList = tables["Bookmarks.List"]
        XCTAssertEqual(bookmarkList.cells.matching(identifier: "Bookmarks.Item").count, 0, file: file, line: line)
        XCTAssertEqual(bookmarkList.cells.matching(identifier: "Bookmarks.Folder").count, 0, file: file, line: line)
    }

    func openAutocompleteSuggestion(
        withIdentifierPrefix identifierPrefix: String,
        file: StaticString = #filePath,
        line: UInt = #line) {
        // Existing suggestion identifiers append unique data; select only by the semantic role prefix.
        let suggestion = descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
            .firstMatch
        suggestion.tapWhenHittable(file: file, line: line)
    }

    func createBookmarkFolder(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line) {
        XCTContext.runActivity(named: "Create bookmark folder \(name)") { _ in
            let editor = tables["Bookmarks.Editor.List"]
            let addFolder = editor.cells["Bookmarks.Editor.AddFolder"]
            editor.swipeUpToReveal(addFolder, file: file, line: line)
            addFolder.tapWhenHittable(file: file, line: line)

            let title = textFields["Bookmarks.Editor.FolderTitle"]
            title.tapWhenHittable(file: file, line: line)
            title.typeText(name)
            buttons["Bookmarks.Editor.FolderSave"]
                .tapWhenHittable(file: file, line: line)

            XCTAssertTrue(
                title.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
                "Folder editor did not close after saving.", file: file, line: line)
            XCTAssertTrue(
                editor.staticTexts[name].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Saved folder did not appear as a bookmark location.", file: file, line: line)
        }
    }

    func saveBookmarkEditor(file: StaticString = #filePath, line: UInt = #line) {
        buttons.matching(identifier: "Bookmarks.Editor.Save").firstMatch
            .tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            tables["Bookmarks.List"].wait(
                for: NSPredicate(format: "exists == true AND isHittable == true"),
                timeout: UITestTimeouts.elementExistence),
            "Bookmarks list did not reappear after saving.", file: file, line: line)
    }

    func deleteBookmark(_ bookmark: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTContext.runActivity(named: "Delete bookmark from the editor") { _ in
            buttons["Bookmarks.Edit"].tapWhenHittable(file: file, line: line)
            bookmark.tapWhenHittable(file: file, line: line)

            let editor = tables["Bookmarks.Editor.List"]
            let delete = editor.cells["Bookmarks.Editor.Delete"]
            if keyboards.firstMatch.exists {
                // Trigger the storyboard's on-drag keyboard dismissal without pulling down the editor sheet.
                let dragStart = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                let dragEnd = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
                XCTAssertTrue(
                    keyboards.firstMatch.wait(
                        for: NSPredicate(format: "exists == false"),
                        timeout: UITestTimeouts.elementExistence),
                    "Keyboard did not dismiss before deleting the bookmark.", file: file, line: line)
            }
            editor.swipeUpToReveal(delete, file: file, line: line)
            delete.tapWhenHittable(file: file, line: line)
            buttons.matching(identifier: "Bookmarks.Editor.ConfirmDelete").firstMatch
                .tapWhenHittable(file: file, line: line)
        }
    }

    func closeBookmarksAfterEditing(file: StaticString = #filePath, line: UInt = #line) {
        buttons["Bookmarks.Edit"].tapWhenHittable(file: file, line: line)
        buttons["Bookmarks.Done"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.elementExistence),
            "Browser did not reappear after closing Bookmarks.", file: file, line: line)
    }

    func resetBookmarks(file: StaticString = #filePath, line: UInt = #line) {
        XCTContext.runActivity(named: "Reset bookmarks and favorites") { _ in
            let menuButton = buttons["Browser.Toolbar.Button.Menu"]
            XCTAssertTrue(
                menuButton.wait(for: NSPredicate(format: "isHittable == true AND isEnabled == true"), timeout: UITestTimeouts.elementExistence),
                "Toolbar menu button did not become available.", file: file, line: line)
            menuButton.press(forDuration: 1)

            let debugList = descendants(matching: .any)["Debug.List"]
            guard debugList.waitForExistence(timeout: UITestTimeouts.navigation) else {
                XCTFail(
                    "Debug screen did not appear. Bookmark reset requires a Debug build or an internal-user build.",
                    file: file,
                    line: line)
                return
            }

            let filter = searchFields.matching(
                NSPredicate(format: "placeholderValue == %@", "Filter")
            ).firstMatch
            filter.tapWhenHittable(file: file, line: line)
            filter.typeText("Bookmarks")

            let bookmarksDebug = descendants(matching: .any)["Debug.Screen.Bookmarks"]
            bookmarksDebug.tapWhenHittable(file: file, line: line)

            buttons["Debug.Bookmarks.DeleteAll"].tapWhenHittable(file: file, line: line)
            buttons.matching(identifier: "Debug.Bookmarks.ConfirmDelete").firstMatch
                .tapWhenHittable(file: file, line: line)

            // The completion button is only presented after the asynchronous reset saves successfully.
            buttons.matching(identifier: "Debug.Bookmarks.ResetComplete").firstMatch
                .tapWhenHittable(file: file, line: line)
            let bookmarksNavigationBar = navigationBars.containing(
                .button,
                identifier: "Debug.Bookmarks.DeleteAll"
            ).firstMatch
            bookmarksNavigationBar.swipeDown()
            XCTAssertTrue(
                debugList.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
                "Debug screen did not close after resetting bookmarks.", file: file, line: line)
        }
    }

}
