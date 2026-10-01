//
//  XCUIApplicationExtension.swift
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

    // The omnibar can be exposed as either a search field or a text field while editing.
    var searchEntry: XCUIElement {
        descendants(matching: .any)["searchEntry"]
    }

    func enterSearchText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.navigation),
            "Search entry did not become tappable.", file: file, line: line)
        searchEntry.tap()
        // Focusing the omnibar selects the existing URL, so typing replaces it.
        searchEntry.typeText(text)
    }

    func openURL(_ url: String, expecting pageText: String, file: StaticString = #filePath, line: UInt = #line) {
        enterSearchText("\(url)\r", file: file, line: line)
        assertPageContains(pageText, file: file, line: line)
    }

    func assertPageContains(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        // Scope to web content so a tab card or autocomplete suggestion cannot satisfy the assertion.
        let content = webViews.staticTexts[text]
        XCTAssertTrue(
            content.waitForExistence(timeout: UITestTimeouts.navigation),
            "Expected page content '\(text)' did not appear.", file: file, line: line)
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

    func openBrowsingMenuItem(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = openBrowsingMenu(revealing: identifier, file: file, line: line)
        item.tapWhenHittable(file: file, line: line)
    }

    func openBrowsingMenu(revealing identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        // The browser menu lives in the toolbar on iPhone and the omnibar on full-width iPad.
        buttons.matching(NSPredicate(format: "identifier IN %@", [
            "Browser.Toolbar.Button.Menu",
            "Browser.OmniBar.Button.BrowsingMenu",
        ])).firstMatch.tapWhenHittable(file: file, line: line)
        let menu = descendants(matching: .any)["Browser.Menu.List"]
        let item = descendants(matching: .any)[identifier]
        let deadline = Date().addingTimeInterval(UITestTimeouts.navigation)
        guard menu.waitForExistence(timeout: UITestTimeouts.elementExistence) else {
            XCTFail("Browsing menu did not appear.", file: file, line: line)
            return item
        }

        let targetIsInteractive = NSPredicate { _, _ in
            guard item.exists else { return false }
            let frame = item.frame
            // SwiftUI can expose an off-screen row with an empty or null frame;
            // asking XCTest for its hit point in that state can raise an error.
            guard !frame.isEmpty, !frame.isNull, !frame.isInfinite else { return false }
            return item.isEnabled && item.isHittable
        }

        // Scrolling can expand the sheet before moving its contents. Wait for the target
        // to become tappable rather than depending on the system grabber or detent state.
        while Date() < deadline {
            if targetIsInteractive.evaluate(with: item) {
                return item
            }
            menu.swipeUp(velocity: .slow)
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 && item.wait(for: targetIsInteractive, timeout: min(1, remaining)) {
                return item
            }
        }

        XCTContext.runActivity(named: "Browsing menu reveal failure: \(identifier)") { activity in
            activity.add(XCTAttachment(string: menu.debugDescription))
            activity.add(XCTAttachment(screenshot: screenshot()))
        }
        XCTFail("Browsing menu item '\(identifier)' did not become tappable.", file: file, line: line)
        return item
    }

    func dismissAddressBarEditing(file: StaticString = #filePath, line: UInt = #line) {
        let menuButton = buttons["Browser.Toolbar.Button.Menu"]
        if menuButton.isHittable {
            return
        }

        // Classic omnibar editing uses Cancel; the unified input overlay uses Back.
        let cancelButton = buttons["Cancel"].firstMatch
        let backButton = buttons["Back"].firstMatch
        if cancelButton.isHittable {
            cancelButton.tap()
        } else {
            backButton.tapWhenHittable(file: file, line: line)
        }

        XCTAssertTrue(
            menuButton.wait(
                for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
                timeout: UITestTimeouts.elementExistence),
            "Browser controls did not appear after dismissing address-bar editing.", file: file, line: line)
    }

    func openTabSwitcher(file: StaticString = #filePath, line: UInt = #line) {
        buttons["Browser.Toolbar.Button.TabSwitcher"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            buttons["TabSwitcher.Button.NewTab"].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Tab switcher did not appear.", file: file, line: line)
    }

    func openNewTab(file: StaticString = #filePath, line: UInt = #line) {
        openTabSwitcher(file: file, line: line)
        buttons["TabSwitcher.Button.NewTab"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.elementExistence),
            "Search entry did not appear in the new tab.", file: file, line: line)
    }

    func tabCell(at index: Int) -> XCUIElement {
        let cells = collectionViews["TabSwitcher.Collection.Tabs"].cells
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "TabSwitcher.Tab."))
        // Retain the tab's identity so later lookups do not depend on its position.
        let identifier = cells.element(boundBy: index).identifier
        return cells.matching(identifier: identifier).element
    }

    func assertTabCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        // These small scenarios keep all tab cards on screen; no localized count label is involved.
        let collection = collectionViews["TabSwitcher.Collection.Tabs"]
        XCTAssertTrue(
            collection.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Tab collection did not appear.", file: file, line: line)
        let tabs = collection.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "TabSwitcher.Tab."))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: tabs)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: UITestTimeouts.elementExistence), .completed,
            "Expected \(count) tabs, found \(tabs.count).", file: file, line: line)
    }

    func assertTabSwitcherTitle(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let titleLabel = staticTexts["TabSwitcher.Title"]
        XCTAssertTrue(
            titleLabel.wait(for: NSPredicate(format: "label == %@", title), timeout: UITestTimeouts.elementExistence),
            "Expected tab switcher title '\(title)', found '\(titleLabel.label)'.", file: file, line: line)
    }
}

extension XCUIElement {

    func tapWhenHittable(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            wait(for: NSPredicate(format: "isHittable == true AND isEnabled == true"), timeout: UITestTimeouts.elementExistence),
            "Element did not become tappable: \(self)", file: file, line: line)
        tap()
    }
}
