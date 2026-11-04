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

    var browserWindow: XCUIElement {
        windows["Browser.Window.Main"]
    }

    // Background snapshot overlays can expose another omnibar with the same identifier.
    // The omnibar can be exposed as either a search field or a text field while editing.
    var searchEntry: XCUIElement {
        browserWindow.descendants(matching: .any)["searchEntry"]
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
        if !exists || ProcessInfo.processInfo.environment["UITEST_HELPER_DIAGNOSTICS"] == "1" {
            let attachment = XCTAttachment(string: timing)
            attachment.name = "Page content wait timing"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "Record page content wait timing") { activity in
                activity.add(attachment)
            }
        }
        XCTAssertTrue(
            exists,
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
        suggestion.tapWhenHittable(in: self, file: file, line: line)
    }

    func openBrowsingMenuItem(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = openBrowsingMenu(revealing: identifier, file: file, line: line)
        item.tapWhenHittable(in: self, file: file, line: line)
    }

    func openBrowsingMenu(revealing identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        dismissAddressBarEditing(file: file, line: line)
        // The menu can be exposed through the toolbar or the iPad omnibar.
        let menuIdentifiers = UIDevice.current.userInterfaceIdiom == .pad
            ? ["Browser.OmniBar.Button.BrowsingMenu", "Browser.Toolbar.Button.Menu"]
            : ["Browser.Toolbar.Button.Menu", "Browser.OmniBar.Button.BrowsingMenu"]
        let preferredMenuButton = browserWindow.buttons[menuIdentifiers[0]]
        let fallbackMenuButton = browserWindow.buttons[menuIdentifiers[1]]
        let menuButton = preferredMenuButton.isHittableInAppWindow(in: self)
            ? preferredMenuButton
            : fallbackMenuButton.isHittableInAppWindow(in: self) ? fallbackMenuButton : preferredMenuButton
        menuButton.tapWhenHittable(in: self, file: file, line: line)
        let menu = descendants(matching: .any)["Browser.Menu.List"]
        let item = descendants(matching: .any)[identifier]
        let deadline = Date().addingTimeInterval(UITestTimeouts.navigation)
        guard menu.waitForExistence(timeout: UITestTimeouts.elementExistence) else {
            XCTFail("Browsing menu did not appear.", file: file, line: line)
            return item
        }

        let targetIsInteractive = NSPredicate { _, _ in
            item.isHittableInAppWindow(in: self)
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
        let timeout: TimeInterval = 20
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + timeout
        var completedPasses = 0
        var passElapsed: TimeInterval = 0
        var lastSummary = "No completed pass; keyboard/tabSwitcher/menu: not-evaluated."
        let ready = XCTContext.runActivity(named: "Dismiss address editing and wait for browser controls") { activity -> Bool in
            var succeeded = false
            while ProcessInfo.processInfo.systemUptime < deadline {
                let passStartedAt = ProcessInfo.processInfo.systemUptime
                let observation = observeAddressBarEditing()
                completedPasses += 1
                passElapsed = ProcessInfo.processInfo.systemUptime - passStartedAt
                lastSummary = observation.summary
                // Accept a completed ready observation even if its AX queries crossed the polling deadline.
                if observation.toolbarReady {
                    succeeded = true
                    break
                }
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                if let dismissButton = observation.dismissButton, dismissButton.exists {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                    dismissButton.tap()
                    continue
                }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                if remaining > 0 {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: min(0.1, remaining)))
                }
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            if !succeeded || ProcessInfo.processInfo.environment["UITEST_HELPER_DIAGNOSTICS"] == "1" {
                let timing = XCTAttachment(string: "timeout=\(timeout)s, elapsed=\(String(format: "%.3f", elapsed))s, completedPasses=\(completedPasses), ready=\(succeeded), passElapsed=\(String(format: "%.3f", passElapsed))s\n\(lastSummary)")
                timing.name = "Address editing dismissal readiness"
                timing.lifetime = .keepAlways
                activity.add(timing)
            }
            return succeeded
        }
        XCTAssertTrue(ready, "Browser controls did not become ready within \(timeout)s after dismissing address-bar editing.\n\(lastSummary)", file: file, line: line)
    }

    private func observeAddressBarEditing() -> (dismissButton: XCUIElement?, toolbarReady: Bool, summary: String) {
        let window = browserWindow
        guard window.exists else {
            return (nil, false, "window: not found; dismiss/keyboard/tabSwitcher/menu: not-evaluated")
        }
        let windowFrame = window.frame
        guard windowFrame.origin.x.isFinite, windowFrame.origin.y.isFinite,
              windowFrame.width.isFinite, windowFrame.height.isFinite,
              windowFrame.width > 0, windowFrame.height > 0 else {
            return (nil, false, "window: invalid geometry \(windowFrame); dismiss/keyboard/tabSwitcher/menu: not-evaluated")
        }
        func readiness(of element: XCUIElement) -> (ready: Bool, reason: String) {
            guard element.exists else { return (false, "not found") }
            let frame = element.frame
            guard frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0, windowFrame.intersects(frame) else {
                return (false, "invalid/off-screen geometry: \(frame)")
            }
            guard element.isEnabled else { return (false, "disabled") }
            let hittable = element.isHittable
            return (hittable, hittable ? "ready" : "not hittable (frame: \(frame))")
        }

        var summary = "window: ready (frame: \(windowFrame))"
        for identifier in ["Browser.OmniBar.Button.Dismiss", "UnifiedToggleInput.Button.Dismiss"] {
            let button = window.buttons[identifier]
            let result = readiness(of: button)
            summary += "\n\(identifier): \(result.reason)"
            if result.ready { return (button, false, summary + "\nkeyboard/tabSwitcher/menu: not-evaluated") }
        }
        let keyboardExists = keyboards.firstMatch.exists
        summary += "\nkeyboardExists: \(keyboardExists)"
        guard !keyboardExists else { return (nil, false, summary + "\ntabSwitcher/menu: not-evaluated") }
        let tabSwitcher = readiness(of: window.buttons["Browser.Toolbar.Button.TabSwitcher"])
        summary += "\ntabSwitcher: \(tabSwitcher.reason)"
        guard tabSwitcher.ready else { return (nil, false, summary + "\nmenu: not-evaluated") }
        let menuIdentifiers = UIDevice.current.userInterfaceIdiom == .pad
            ? ["Browser.OmniBar.Button.BrowsingMenu", "Browser.Toolbar.Button.Menu"]
            : ["Browser.Toolbar.Button.Menu", "Browser.OmniBar.Button.BrowsingMenu"]
        for identifier in menuIdentifiers {
            let result = readiness(of: window.buttons[identifier])
            summary += "\n\(identifier): \(result.reason)"
            if result.ready { return (nil, true, summary) }
        }
        return (nil, false, summary)
    }

    func openTabSwitcher(file: StaticString = #filePath, line: UInt = #line) {
        dismissAddressBarEditing(file: file, line: line)
        browserWindow.buttons["Browser.Toolbar.Button.TabSwitcher"].tapWhenHittable(in: self, file: file, line: line)
        XCTAssertTrue(
            browserWindow.buttons["TabSwitcher.Button.Done"].waitForHittableInAppWindow(in: self, timeout: UITestTimeouts.elementExistence),
            "Tab switcher did not appear.", file: file, line: line)
    }

    func openNewTab(file: StaticString = #filePath, line: UInt = #line) {
        openTabSwitcher(file: file, line: line)
        browserWindow.buttons["TabSwitcher.Button.NewTab"].tapWhenHittable(in: self, file: file, line: line)
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
        let observation = waitForAppWindowReadiness(in: application, timeout: timeout)
        if !observation.ready {
            let attachment = XCTAttachment(string: "timeout=\(timeout)s, completedPasses=\(observation.passes), lastObservation=\(observation.reason)")
            attachment.name = "App window readiness timeout"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "Record app window readiness timeout") { activity in
                activity.add(attachment)
            }
        }
        return observation.ready
    }

    func isHittableInAppWindow(in application: XCUIApplication) -> Bool {
        appWindowReadiness(in: application).ready
    }

    private func appWindowReadiness(in application: XCUIApplication) -> (ready: Bool, reason: String) {
        guard exists else { return (false, "not found") }
        let frame = self.frame
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return (false, "invalid element geometry: \(frame)") }

        let window = application.windows.firstMatch
        guard window.exists else { return (false, "app window not found") }
        let windowFrame = window.frame
        guard windowFrame.origin.x.isFinite, windowFrame.origin.y.isFinite,
              windowFrame.width.isFinite, windowFrame.height.isFinite,
              windowFrame.width > 0, windowFrame.height > 0 else { return (false, "invalid app window geometry: \(windowFrame)") }
        guard windowFrame.intersects(frame) else { return (false, "outside app window: \(frame)") }
        guard isEnabled else { return (false, "disabled") }
        let hittable = isHittable
        return (hittable, hittable ? "ready" : "not hittable (frame: \(frame))")
    }

    private func waitForAppWindowReadiness(in application: XCUIApplication, timeout: TimeInterval) -> (ready: Bool, reason: String, passes: Int) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var lastReason = "no observation before deadline"
        var passes = 0
        while ProcessInfo.processInfo.systemUptime < deadline {
            let observation = appWindowReadiness(in: application)
            passes += 1
            lastReason = observation.reason
            // AX queries can cross the deadline; retain a completed ready observation.
            if observation.ready { return (true, lastReason, passes) }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: min(0.1, remaining)))
            }
        }
        return (false, lastReason, passes)
    }

    func tapWhenHittable(in application: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let timeout = UITestTimeouts.elementExistence
        let startedAt = ProcessInfo.processInfo.systemUptime
        let observation = waitForAppWindowReadiness(in: application, timeout: timeout)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let timing = """
        source=\(file):\(line)
        timeout=\(timeout)s
        elapsed=\(String(format: "%.3f", elapsed))s
        completedPasses=\(observation.passes)
        becameTappable=\(observation.ready)
        lastObservation=\(observation.reason)
        """
        if !observation.ready || ProcessInfo.processInfo.environment["UITEST_HELPER_DIAGNOSTICS"] == "1" {
            let attachment = XCTAttachment(string: timing)
            attachment.name = "Tappability wait timing"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "Record tappability wait timing") { activity in
                activity.add(attachment)
            }
        }
        XCTAssertTrue(
            observation.ready,
            "Element did not become tappable: \(observation.reason)", file: file, line: line)
        guard observation.ready else { return }
        tap()
    }
}
