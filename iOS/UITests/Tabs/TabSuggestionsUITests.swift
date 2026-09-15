//
//  TabSuggestionsUITests.swift
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

final class TabSuggestionsUITests: UITestCase {

    func testWhenOpenTabSuggestionIsSelectedThenExistingTabIsShown() {
        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
        app.openNewTab()
        app.openURL("https://www.search-company.site", expecting: "Search engine")

        app.enterSearchText("privacy")
        app.descendants(matching: .any)["Autocomplete.Suggestions.ListItem.OpenTab-privacy-test-pages.site"].tapWhenHittable()
        app.assertPageContains("Privacy Test Pages")

        app.enterSearchText("ad click")
        app.descendants(matching: .any)["Autocomplete.Suggestions.ListItem.OpenTab-search-company.site"].tapWhenHittable()
        app.assertPageContains("Search engine")

        app.openTabSwitcher()
        app.assertTabCount(2)
    }

    func testWhenOpenTabSuggestionIsSelectedFromNewTabThenEmptyTabIsRemoved() {
        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
        app.openNewTab()

        app.enterSearchText("privacy")
        app.descendants(matching: .any)["Autocomplete.Suggestions.ListItem.OpenTab-privacy-test-pages.site"].tapWhenHittable()
        app.assertPageContains("Privacy Test Pages")

        app.openTabSwitcher()
        app.assertTabCount(1)
        app.tabCell(at: 0).buttons["TabSwitcher.Tab.Open"].tapWhenHittable()
        app.assertPageContains("Privacy Test Pages")
    }
}
