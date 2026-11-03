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
            searchEntry.waitForHittableInAppWindow(in: self, timeout: UITestTimeouts.navigation),
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
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timeout = UITestTimeouts.navigation
        let exists = content.waitForExistence(timeout: timeout)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let timing = """
        text=\(text)
        timeout=\(timeout)s
        elapsed=\(String(format: "%.3f", elapsed))s
        exists=\(exists)
        exceedsOriginalThirtySecondNavigationTimeout=\(elapsed > 30.0)
        """
        let attachment = XCTAttachment(string: timing)
        attachment.name = "Page content wait timing"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Record page content wait timing") { activity in
            activity.add(attachment)
        }
        XCTAssertTrue(
            exists,
            "Expected page content '\(text)' did not appear.", file: file, line: line)
    }

    func dismissAddressBarEditing(file: StaticString = #filePath, line: UInt = #line) {
        let dismissButtons = buttons.matching(NSPredicate(format: "identifier IN %@", [
            "Browser.OmniBar.Button.Dismiss", "UnifiedToggleInput.Button.Dismiss"
        ]))
        let activeDismissButton = {
            dismissButtons.allElementsBoundByIndex.first { $0.isHittableInAppWindow(in: self) }
        }
        let menuButtons = buttons.matching(NSPredicate(format: "identifier IN %@", [
            "Browser.Toolbar.Button.Menu", "Browser.OmniBar.Button.BrowsingMenu"
        ]))
        let tabSwitcher = buttons["Browser.Toolbar.Button.TabSwitcher"]
        let toolbarIsReady = NSPredicate { _, _ in
            !self.keyboards.firstMatch.exists &&
                activeDismissButton() == nil &&
                tabSwitcher.isHittableInAppWindow(in: self) &&
                menuButtons.allElementsBoundByIndex.contains { $0.isHittableInAppWindow(in: self) }
        }
        // Hidden toolbar controls can remain exposed beneath the address-input overlay.
        let inputOrToolbarIsReady = NSPredicate { _, _ in
            activeDismissButton() != nil || toolbarIsReady.evaluate(with: self)
        }
        guard wait(for: inputOrToolbarIsReady, timeout: UITestTimeouts.elementExistence) else {
            XCTFail("Neither address-input dismissal nor browser controls became available.", file: file, line: line)
            return
        }
        if let dismissButton = activeDismissButton() {
            dismissButton.tap()
        }

        XCTAssertTrue(
            wait(for: toolbarIsReady, timeout: UITestTimeouts.elementExistence),
            "Browser controls did not appear after dismissing address-bar editing.", file: file, line: line)
    }

    func openTabSwitcher(file: StaticString = #filePath, line: UInt = #line) {
        dismissAddressBarEditing(file: file, line: line)
        buttons["Browser.Toolbar.Button.TabSwitcher"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            buttons["TabSwitcher.Button.Done"].waitForHittableInAppWindow(in: self, timeout: UITestTimeouts.elementExistence),
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

    func waitForHittableInAppWindow(in application: XCUIApplication, timeout: TimeInterval) -> Bool {
        wait(for: NSPredicate { [self] _, _ in
            isHittableInAppWindow(in: application)
        }, timeout: timeout)
    }

    func isHittableInAppWindow(in application: XCUIApplication) -> Bool {
        guard exists else { return false }
        let frame = self.frame
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return false }

        let window = application.windows.firstMatch
        guard window.exists else { return false }
        let windowFrame = window.frame
        guard windowFrame.width > 0, windowFrame.height > 0,
              windowFrame.intersects(frame) else { return false }
        return isEnabled && isHittable
    }

    func tapWhenHittable(file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "isHittable == true AND isEnabled == true")
        let timeout = UITestTimeouts.elementExistence
        let startedAt = ProcessInfo.processInfo.systemUptime
        let becameTappable = wait(for: predicate, timeout: timeout)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let timing = """
        source=\(file):\(line)
        predicate=\(predicate.predicateFormat)
        timeout=\(timeout)s
        elapsed=\(String(format: "%.3f", elapsed))s
        becameTappable=\(becameTappable)
        """
        let attachment = XCTAttachment(string: timing)
        attachment.name = "Tappability wait timing"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Record tappability wait timing") { activity in
            activity.add(attachment)
        }
        XCTAssertTrue(
            becameTappable,
            "Element did not become tappable: \(self)", file: file, line: line)
        tap()
    }
}
