//
//  FavoritesUITests.swift
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

final class FavoritesUITests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.resetBookmarks()
    }

    func testWhenPageIsFavoritedThenItCanBeOpenedFromNewTabAndRemoved() {
        let favorite = app.buttons["Favorites.Item"].firstMatch
        let favoriteSuggestion = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "Autocomplete.Suggestions.ListItem.Favorite-"))
            .firstMatch
        let bookmark = app.tables["Bookmarks.List"].cells["Bookmarks.Item"].firstMatch

        XCTContext.runActivity(named: "Add, remove, and restore the favorite") { _ in
            app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
            app.openBrowsingMenuItem("Browser.Menu.AddFavorite")
            app.openBrowsingMenuItem("Browser.Menu.RemoveFavorite")
            app.openBrowsingMenuItem("Browser.Menu.AddFavorite")
        }

        XCTContext.runActivity(named: "Open the favorite from the new-tab page") { _ in
            app.openNewTab()
            app.buttons["UnifiedToggleInput.Button.Dismiss"].tapWhenHittable()
            XCTAssertTrue(
                favorite.wait(
                    for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
                    timeout: UITestTimeouts.navigation),
                "Favorite did not appear on the new-tab page.")
            favorite.tap()
            app.assertPageContains("Privacy Test Pages")
        }

        XCTContext.runActivity(named: "Verify the favorite appears in autocomplete") { _ in
            app.enterSearchText("pri")
            XCTAssertTrue(
                favoriteSuggestion.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Favorite did not appear in autocomplete suggestions.")
            app.buttons["UnifiedToggleInput.Button.Dismiss"].tapWhenHittable()
        }

        XCTContext.runActivity(named: "Delete the favorite from Bookmarks") { _ in
            app.openBookmarks()
            XCTAssertTrue(
                bookmark.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Favorite did not appear in Bookmarks.")
            app.deleteBookmark(bookmark)
            app.assertBookmarksEmpty()
            app.closeBookmarksAfterEditing()
        }

        XCTContext.runActivity(named: "Verify the favorite is absent from the new-tab page") { _ in
            app.openNewTab()
            app.buttons["UnifiedToggleInput.Button.Dismiss"].tapWhenHittable()
            XCTAssertTrue(
                favorite.wait(
                    for: NSPredicate(format: "exists == false"),
                    timeout: UITestTimeouts.elementExistence),
                "The removed favorite is still on the new-tab page.")
        }
    }
}
