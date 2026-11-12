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

    override var additionalLaunchEnvironment: [String: String] {
        [
            "UITEST_DISABLE_ANIMATIONS": "1",
            "UITEST_TEMPORARY_BOOKMARKS_STORE": "1"
        ]
    }

    func testWhenPageIsFavoritedThenItCanBeOpenedFromNewTabAndRemoved() throws {
        let site = try localWebsite()
        let favorite = app.buttons["Favorites.Item"].firstMatch
        let favoriteSuggestion = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "Autocomplete.Suggestions.ListItem.Favorite-"))
            .firstMatch
        let bookmark = app.tables["Bookmarks.List"].cells["Bookmarks.Item"].firstMatch

        XCTContext.runActivity(named: "Add, remove, and restore the favorite") { _ in
            site.open(.first, in: app)
            app.openBrowsingMenuItem("Browser.Menu.AddFavorite")
            app.openBrowsingMenuItem("Browser.Menu.RemoveFavorite")
            app.openBrowsingMenuItem("Browser.Menu.AddFavorite")
        }

        XCTContext.runActivity(named: "Open the favorite from the new-tab page") { _ in
            app.openNewTab()
            app.buttons["UnifiedToggleInput.Button.Dismiss"].tapWhenHittable(in: app)
            XCTAssertTrue(
                favorite.wait(
                    for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
                    timeout: UITestTimeouts.navigation),
                "Favorite did not appear on the new-tab page.")
            favorite.tap()
            app.assertPageContains(LocalUITestWebsite.Page.first.title)
        }

        XCTContext.runActivity(named: "Verify the favorite appears in autocomplete") { _ in
            app.enterSearchText("first")
            XCTAssertTrue(
                favoriteSuggestion.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Favorite did not appear in autocomplete suggestions.")
            app.buttons["UnifiedToggleInput.Button.Dismiss"].tapWhenHittable(in: app)
        }

        XCTContext.runActivity(named: "Delete the favorite from Bookmarks") { _ in
            app.openBookmarks()
            XCTAssertTrue(
                bookmark.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Favorite did not appear in Bookmarks.")
            app.buttons["Bookmarks.Edit"].tapWhenHittable(in: app)
            let removeBookmark = bookmark.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Remove")
            ).firstMatch
            removeBookmark.tapWhenHittable(in: app)
            app.tables["Bookmarks.List"].buttons["Delete"].tapWhenHittable(in: app)
            app.assertBookmarksEmpty()
            app.closeBookmarksAfterEditing()
        }

        XCTContext.runActivity(named: "Verify the favorite is absent from the new-tab page") { _ in
            app.openNewTab()
            app.buttons["UnifiedToggleInput.Button.Dismiss"].tapWhenHittable(in: app)
            XCTAssertTrue(
                favorite.wait(
                    for: NSPredicate(format: "exists == false"),
                    timeout: UITestTimeouts.elementExistence),
                "The removed favorite is still on the new-tab page.")
        }
    }
}
