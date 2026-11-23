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

    override var additionalLaunchEnvironment: [String: String] {
        super.additionalLaunchEnvironment.merging([
            "UITEST_DISABLE_ANIMATIONS": "1"
        ]) { _, new in new }
    }

    func testWhenOpenTabSuggestionIsSelectedThenExistingTabIsShown() throws {
        let site = try localWebsite()
        XCTContext.runActivity(named: "Create two tabs") { _ in
            site.open(.first, in: app)
            app.openNewTab()
            site.open(.second, in: app)
        }

        XCTContext.runActivity(named: "Switch to the first tab from autocomplete") { _ in
            app.enterSearchText("first")
            openSuggestion(for: .first, on: site)
            app.assertPageContains(LocalUITestWebsite.Page.first.title)
        }

        XCTContext.runActivity(named: "Switch to the second tab from autocomplete") { _ in
            app.enterSearchText("second")
            openSuggestion(for: .second, on: site)
            app.assertPageContains(LocalUITestWebsite.Page.second.title)
        }

        XCTContext.runActivity(named: "Verify switching did not create another tab") { _ in
            app.openTabSwitcher()
            app.assertTabCount(2)
        }
    }

    func testWhenOpenTabSuggestionIsSelectedFromNewTabThenEmptyTabIsRemoved() throws {
        let site = try localWebsite()
        XCTContext.runActivity(named: "Open an empty tab beside the test page") { _ in
            site.open(.first, in: app)
            app.openNewTab()
        }

        XCTContext.runActivity(named: "Switch from the empty tab using autocomplete") { _ in
            app.enterSearchText("first")
            openSuggestion(for: .first, on: site)
            app.assertPageContains(LocalUITestWebsite.Page.first.title)
        }

        XCTContext.runActivity(named: "Verify the empty tab was removed") { _ in
            app.openTabSwitcher()
            app.assertTabCount(1)
            app.tabCell(at: 0).buttons["TabSwitcher.Tab.Open"].tapWhenHittable(in: app)
            app.assertPageContains(LocalUITestWebsite.Page.first.title)
        }
    }

    private func openSuggestion(for page: LocalUITestWebsite.Page, on site: LocalUITestWebsite, file: StaticString = #filePath, line: UInt = #line) {
        let identifier = "Autocomplete.Suggestions.ListItem.OpenTab-\(site.hostAndPort)\(page.path)"
        app.descendants(matching: .any)[identifier].tapWhenHittable(in: app, file: file, line: line)
    }
}
