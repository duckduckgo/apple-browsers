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
        let labelMatch = webViews.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        let timeout = UITestTimeouts.navigation
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + timeout
        var observations = ["text=\(text)", "timeout=\(timeout)s"]
        var passed = false
        var capturedMismatch = false

        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            let waitResult = content.waitForExistence(timeout: min(5, remaining))
            let waitElapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let keyedNow = content.exists
            let keyedElapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let labelExists = labelMatch.exists
            let labelElapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let keyedExists = (waitResult && waitElapsed <= timeout) || (keyedNow && keyedElapsed <= timeout)
            observations.append(String(format: "wait=%.3fs:%@ keyed=%.3fs:%@ label=%.3fs:%@", waitElapsed, waitResult.description, keyedElapsed, keyedNow.description, labelElapsed, labelExists.description))

            if keyedExists {
                passed = true
                break
            }

            if labelExists && labelElapsed <= timeout {
                let keyedRecheck = content.exists
                let recheckElapsed = ProcessInfo.processInfo.systemUptime - startedAt
                observations.append(String(format: "t=%.3fs keyedRecheck=%@", recheckElapsed, keyedRecheck.description))
                if keyedRecheck && recheckElapsed <= timeout {
                    passed = true
                    break
                }

                if !capturedMismatch && recheckElapsed < timeout {
                    capturedMismatch = true
                    let screenshot = XCTAttachment(screenshot: self.screenshot())
                    screenshot.name = "Page content query mismatch screen"
                    screenshot.lifetime = .keepAlways
                    let hierarchy = XCTAttachment(string: debugDescription)
                    hierarchy.name = "Page content query mismatch hierarchy"
                    hierarchy.lifetime = .keepAlways
                    XCTContext.runActivity(named: "Capture first page content query mismatch") { activity in
                        activity.add(screenshot)
                        activity.add(hierarchy)
                    }
                }
            }
        }

        observations.append(String(format: "result=%@ elapsed=%.3fs", passed.description, ProcessInfo.processInfo.systemUptime - startedAt))
        let trace = XCTAttachment(string: observations.joined(separator: "\n"))
        trace.name = "Page content query observations"
        trace.lifetime = .keepAlways
        XCTContext.runActivity(named: "Record page content query observations") { activity in
            activity.add(trace)
        }
        XCTAssertTrue(
            passed,
            "Expected page content '\(text)' did not appear.", file: file, line: line)
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
