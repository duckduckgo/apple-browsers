//
//  FireSnapshotUITests.swift
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

/// Exercises the presentation while cleanup is held, rather than only checking its final tab count.
final class FireSnapshotUITests: UITestCase, FireDialogUITests {
    private var cleanupRelease: URL?

    private var progressWindow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "FireProgressWindowController.window").firstMatch
    }

    override func tearDown() {
        releaseCleanup()
        app?.terminate()
        if let directory = cleanupRelease?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: directory)
        }
        cleanupRelease = nil
        super.tearDown()
    }

    func testSeparatePinnedTabsSurviveBurnAllWithSnapshotEnabled() throws {
        try assertSeparatePinnedTabsSurvive(snapshotEnabled: true)
    }

    func testSeparatePinnedTabsSurviveBurnAllWithSnapshotDisabled() throws {
        try assertSeparatePinnedTabsSurvive(snapshotEnabled: false)
    }

    private func assertSeparatePinnedTabsSurvive(snapshotEnabled: Bool) throws {
        try launch(snapshotEnabled: snapshotEnabled)
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        app.preferencesWindow.popUpButtons["PreferencesGeneralView.pinnedTabsModePicker"].click()
        app.menuItems["Separate in each window"].click()
        app.closePreferencesWindow()

        openPage(title: "First pinned page")
        app.pinCurrentTab()
        XCTAssertTrue(app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence), app.debugDescription)
        app.openNewTab()
        openPage(title: "First ordinary page")
        XCTAssertEqual(app.pinnedTabs.count, 1, app.debugDescription)
        app.openNewWindow()
        openPage(title: "Second pinned page")
        app.pinCurrentTab()
        XCTAssertTrue(app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: 1), timeout: UITests.Timeouts.elementExistence), app.debugDescription)
        app.openNewTab()
        openPage(title: "Second ordinary page")
        XCTAssertEqual(app.pinnedTabs.count, 1, app.debugDescription)
        XCTAssertEqual(app.windows.count, 2)

        beginBurn(scope: "All data", closeTabs: true)
        waitForCleanupToStart()
        releaseCleanup()
        waitForBurnToFinish()
        XCTAssertEqual(app.windows.allElementsBoundByIndex.reduce(0) { $0 + $1.pinnedTabs.count }, 2,
                       "Both per-window pinned tabs must survive the burn")
        XCTAssertEqual(app.windows.count, 2, "Both pinned windows must remain open")
        let firstOwner = app.windows.containing(.radioButton, identifier: "First pinned page").firstMatch
        let secondOwner = app.windows.containing(.radioButton, identifier: "Second pinned page").firstMatch
        XCTAssertTrue(firstOwner.exists)
        XCTAssertTrue(secondOwner.exists)
        XCTAssertEqual(firstOwner.pinnedTabs.count, 1)
        XCTAssertEqual(secondOwner.pinnedTabs.count, 1)
        XCTAssertFalse(app.tabs["First ordinary page"].exists)
        XCTAssertFalse(app.tabs["Second ordinary page"].exists)
    }

    func testSurvivingWindowRejectsClicksDuringSnapshotCleanup() throws {
        try assertSurvivingWindowRejectsClicks(snapshotEnabled: true)
    }

    func testSurvivingWindowRejectsClicksDuringLegacyCleanup() throws {
        try assertSurvivingWindowRejectsClicks(snapshotEnabled: false)
    }

    private func assertSurvivingWindowRejectsClicks(snapshotEnabled: Bool) throws {
        try launch(snapshotEnabled: snapshotEnabled)
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        app.preferencesWindow.popUpButtons["PreferencesGeneralView.pinnedTabsModePicker"].click()
        app.menuItems["Separate in each window"].click()
        app.closePreferencesWindow()

        let directory = cleanupRelease!.deletingLastPathComponent()
        let clickMarker = directory.appendingPathComponent("click-was-blocked")
        let reloadMarker = directory.appendingPathComponent("waiting-for-pinned-page")
        let clickURL = URL.testsServer.appendingParameter(name: "deleteFiles", value: clickMarker.path)
        let reloadURL = URL.testsServer.appendingParameter(name: "deleteFiles", value: reloadMarker.path)
        // These markers live outside WebKit, so reloading pins or clearing site data cannot erase a click.
        let clickJavaScript = String(data: try JSONEncoder().encode(clickURL.absoluteString), encoding: .utf8)!
        let reloadJavaScript = String(data: try JSONEncoder().encode(reloadURL.absoluteString), encoding: .utf8)!
        let page = UITests.simpleServedPage(titled: "Surviving pinned page", body: """
        <button onclick="recordClick()">Increment</button>
        <script>
        function recordClick() {
            const request = new XMLHttpRequest();
            request.open('GET', \(clickJavaScript), false);
            request.setRequestHeader('Cache-Control', 'no-store');
            request.send();
        }
        addEventListener('load', () => fetch(\(reloadJavaScript), { cache: 'no-store' }));
        </script>
        """)
        app.activateAddressBar()
        app.openURL(page, waitForWebViewAccessibilityLabel: "Surviving pinned page")
        app.pinCurrentTab()
        XCTAssertEqual(app.pinnedTabs.count, 1)
        let survivor = app.windows.matching(NSPredicate(format: "title == %@", "Surviving pinned page")).firstMatch
        let increment = survivor.webViews.buttons["Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: UITests.Timeouts.localTestServer))
        let buttonFrame = increment.frame
        let incrementPoint = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
        try Data().write(to: clickMarker)
        clickScreenPoint(incrementPoint)
        waitForMarkerDeletion(clickMarker)
        try Data().write(to: clickMarker)

        app.openNewWindow()
        openPage(title: "Window to burn")
        let source = app.windows.matching(NSPredicate(format: "title == %@", "Window to burn")).firstMatch
        moveBurnSourceAwayFromSurvivingPage(source, point: incrementPoint)
        try Data().write(to: reloadMarker)
        beginBurn(scope: "All data", closeTabs: true)
        waitForCleanupToStart()
        // Burn all retains this window because its pins are separate, and replaces its pinned page.
        // Wait for that replacement to load before testing input interception.
        waitForMarkerDeletion(reloadMarker)
        for _ in 0..<2 {
            clickScreenPoint(incrementPoint)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: clickMarker.path),
                      "The pinned window must reject input while cleanup is pending")
        releaseCleanup()
        waitForBurnToFinish()
        XCTAssertTrue(progressWindow.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
        XCTAssertTrue(app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
        XCTAssertTrue(survivor.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clickMarker.path),
                      "Blocked clicks must not be delivered after cleanup")
        for _ in 0..<2 {
            clickScreenPoint(incrementPoint)
        }
        waitForMarkerDeletion(clickMarker)
    }

    private func moveBurnSourceAwayFromSurvivingPage(_ source: XCUIElement, point: CGPoint) {
        // Keep the source and its progress panel away from the tested page; otherwise they could
        // consume clicks and hide a missing input blocker in the surviving window.
        let origin = source.coordinate(withNormalizedOffset: .zero)
        source.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -1, dy: -1))
            .click(forDuration: 0.3, thenDragTo: origin.withOffset(CGVector(dx: 800, dy: 650)))
        let titleBar = source.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 400, dy: 15))
        let offset = max(0, point.x + 100 - source.frame.minX)
        titleBar.click(forDuration: 0.3, thenDragTo: titleBar.withOffset(CGVector(dx: offset, dy: 0)))
        XCTAssertGreaterThan(source.frame.minX, point.x, "The source must not cover the input test point")
    }

    private func waitForMarkerDeletion(_ marker: URL) {
        let deleted = expectation(for: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: marker.path)
        }, evaluatedWith: nil)
        wait(for: [deleted], timeout: UITests.Timeouts.fireAnimation)
    }

    func testWholeWindowBurnUsesIndependentProgressAndLeavesUsableFreshWindow() throws {
        try launch(snapshotEnabled: true)
        openPage(title: "Snapshot source page")
        beginBurn(scope: "All data", closeTabs: true)
        waitForCleanupToStart()
        let progress = progressWindow
        XCTAssertTrue(progress.waitForExistence(timeout: UITests.Timeouts.fireAnimation), app.debugDescription)
        XCTAssertFalse(app.webViews["Snapshot source page"].exists)
        XCTAssertFalse(app.fakeFireButton.exists, "The separate panel must not reuse the browser overlay")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "FireProgressWindowController.window").count, 1)
        releaseCleanup()
        waitForBurnToFinish()
        XCTAssertTrue(progress.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
        verifyNewTabPageIsOpen()
        openPage(title: "Fresh window accepts navigation")
        XCTAssertTrue(app.webViews["Fresh window accepts navigation"].exists)
    }

    func testFlagDisabledUsesInWindowProgress() throws {
        try launch(snapshotEnabled: false)
        openPage(title: "Legacy retained window")
        beginBurn(scope: "All data", closeTabs: true)
        waitForCleanupToStart()
        XCTAssertTrue(app.fakeFireButton.waitForExistence(timeout: UITests.Timeouts.fireAnimation))
        XCTAssertFalse(progressWindow.exists)
        releaseCleanup()
        waitForBurnToFinish()
        XCTAssertTrue(app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
        verifyNewTabPageIsOpen()
    }

    func testTabBurnKeepsOtherTabForBothFlagStates() throws {
        for enabled in [false, true] {
            try launch(snapshotEnabled: enabled)
            openPage(title: "Tab to burn")
            app.openNewTab()
            openPage(title: "Tab to retain")
            app.tabs["Tab to burn"].click()
            beginBurn(scope: "From this tab", closeTabs: true)
            waitForCleanupToStart()
            XCTAssertFalse(progressWindow.exists)
            releaseCleanup()
            waitForBurnToFinish()
            XCTAssertTrue(app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
            XCTAssertTrue(app.tabs["Tab to retain"].exists)
            XCTAssertFalse(app.tabs["Tab to burn"].exists)
            XCTAssertEqual(app.windows.count, 1)
            app.terminate()
        }
    }

    func testNonClosingBurnKeepsTabsAndLegacyProgressForBothFlagStates() throws {
        for enabled in [false, true] {
            try launch(snapshotEnabled: enabled)
            openPage(title: "First retained tab")
            app.openNewTab()
            openPage(title: "Second retained tab")
            beginBurn(scope: "All data", closeTabs: false)
            waitForCleanupToStart()
            XCTAssertTrue(app.fakeFireButton.waitForExistence(timeout: UITests.Timeouts.fireAnimation))
            XCTAssertFalse(progressWindow.exists)
            XCTAssertTrue(app.tabs["First retained tab"].exists)
            XCTAssertTrue(app.tabs["Second retained tab"].exists)
            releaseCleanup()
            waitForBurnToFinish()
            XCTAssertTrue(app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
            XCTAssertEqual(app.tabs.count, 2)
            app.terminate()
        }
    }

    func testFireWindowCloseKeepsRegularWindowForBothFlagStates() throws {
        try assertFireWindowCloseKeepsRegularWindow(route: .keyboard)
    }

    func testFireWindowTrafficLightKeepsRegularWindowForBothFlagStates() throws {
        try assertFireWindowCloseKeepsRegularWindow(route: .trafficLight)
    }

    func testClosingLastFireTabKeepsRegularWindowForBothFlagStates() throws {
        try assertFireWindowCloseKeepsRegularWindow(route: .lastTab)
    }

    func testFirePopoverCloseKeepsRegularWindowForBothFlagStates() throws {
        try assertFireWindowCloseKeepsRegularWindow(route: .popover)
    }

    private enum CloseRoute {
        case keyboard, trafficLight, lastTab, popover
    }

    private func assertFireWindowCloseKeepsRegularWindow(route: CloseRoute) throws {
        for enabled in [false, true] {
            try launch(snapshotEnabled: enabled)
            openPage(title: "Regular window retained")
            app.openFireWindow()
            openPage(title: "Private window closing")
            switch route {
            case .keyboard: app.closeWindow()
            case .trafficLight: app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
            case .lastTab: app.typeKey("w", modifierFlags: .command)
            case .popover:
                app.fireButton.click()
                app.buttons["Close and Burn This Window"].click()
            }
            XCTAssertTrue(app.webViews["Private window closing"].waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
            XCTAssertTrue(app.webViews["Regular window retained"].exists)
            XCTAssertFalse(progressWindow.exists)
            XCTAssertTrue(app.wait(for: .keyPath(\.windows.count, equalTo: 1), timeout: UITests.Timeouts.fireAnimation),
                          "The private window and its temporary snapshot must both disappear")
            app.terminate()
        }
    }

    func testBurningLastRegularTabKeepsLastWindowForBothFlagStates() throws {
        for enabled in [false, true] {
            try launch(snapshotEnabled: enabled)
            openPage(title: "Only regular tab")
            XCTAssertEqual(app.tabs.count, 1)
            beginBurn(scope: "From this tab", closeTabs: true)
            waitForCleanupToStart()
            XCTAssertFalse(progressWindow.exists)
            releaseCleanup()
            waitForBurnToFinish()
            verifyNewTabPageIsOpen()
            XCTAssertEqual(app.windows.count, 1)
            XCTAssertEqual(app.tabs.count, 1)
            app.terminate()
        }
    }

    private func launch(snapshotEnabled: Bool, simplified: Bool = true) throws {
        releaseCleanup()
        if let directory = cleanupRelease?.deletingLastPathComponent() {
            try FileManager.default.removeItem(at: directory)
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FireSnapshotUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let release = directory.appendingPathComponent("release")
        cleanupRelease = release
        try Data().write(to: release)
        app = XCUIApplication.setUp(environment: [
            "FIRE_UI_TEST_PLAY_ANIMATIONS": "1",
            "FIRE_UI_TEST_CLEANUP_RELEASE": release.path
        ], featureFlags: ["fireWindowSnapshotAnimation": snapshotEnabled, "fireDialogSimplified": simplified],
                                   arguments: ["-fireAnimationEnabled", "true"])
        app.disableWarnBeforeClosingPinnedTabs()
        app.enforceSingleWindow()
        for _ in 0..<20 where app.pinnedTabs.count > 0 {
            let count = app.pinnedTabs.count
            // The context menu targets the pin even when its window or another tab was selected.
            app.pinnedTabs.firstMatch.rightClick()
            app.menuItems["Unpin Tab"].clickAfterExistenceTestSucceeds()
            XCTAssertTrue(app.wait(for: .keyPath(\.pinnedTabs.count, equalTo: count - 1), timeout: UITests.Timeouts.elementExistence))
        }
        app.openPreferencesWindow()
        app.preferencesGoToDataClearingPane()
        app.setOpenFireWindowByDefault(enabled: false)
        app.closePreferencesWindow()
        // Start from an empty ordinary window without waiting on a presentation from another test.
        openPage(title: "Initial cleanup page")
        beginBurn(scope: simplified ? "All data" : "Everything", closeTabs: true)
        waitForCleanupToStart()
        waitForBurnToFinish()
        XCTAssertTrue(progressWindow.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
        XCTAssertTrue(app.fakeFireButton.waitForNonExistence(timeout: UITests.Timeouts.fireAnimation))
        verifyNewTabPageIsOpen()
        app.enforceSingleWindow()
        try FileManager.default.removeItem(at: release)
        try FileManager.default.removeItem(atPath: release.path + ".started")
        try FileManager.default.removeItem(atPath: release.path + ".finished")
    }

    private func openPage(title: String) {
        let page = UITests.simpleServedPage(titled: title, body: """
        <script>document.cookie="fire-regression=1; path=/";</script>
        <p>Sample text for \(title)</p>
        """)
        app.activateAddressBar()
        app.openURL(page, waitForWebViewAccessibilityLabel: title)
        XCTAssertTrue(app.webViews[title].staticTexts["Sample text for \(title)"].waitForExistence(timeout: UITests.Timeouts.localTestServer))
    }

    private func clickScreenPoint(_ point: CGPoint) {
        // The menu bar stays accessible while browser windows are covered. The application's
        // own frame can be infinite on macOS, so it cannot anchor a real screen click.
        let menuBarOrigin = app.menuBars.firstMatch.coordinate(withNormalizedOffset: .zero)
        let originPoint = menuBarOrigin.screenPoint
        XCTAssertTrue(originPoint.x.isFinite && originPoint.y.isFinite, "Screen clicks require a finite anchor")
        menuBarOrigin.withOffset(CGVector(dx: point.x - originPoint.x, dy: point.y - originPoint.y)).click()
    }

    private func beginBurn(scope: String, closeTabs: Bool) {
        app.fireButton.click()
        XCTAssertTrue(fireDialogTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.fireDialogSegmentedControl.buttons[scope].click()
        if fireDialogDetailsDisclosureButton.exists, (fireDialogDetailsDisclosureButton.value as? String) != "expanded" {
            fireDialogDetailsDisclosureButton.click()
        }
        fireDialogTabsToggle.toggleCheckboxIfNeeded(to: closeTabs, validate: true, ensureHittable: { _ in })
        fireDialogHistoryToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogCookiesToggle.toggleCheckboxIfNeeded(to: true, validate: true, ensureHittable: { _ in })
        fireDialogBurnButton.click()
    }

    private func waitForCleanupToStart() {
        let path = cleanupRelease!.path + ".started"
        let started = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: path) }, evaluatedWith: nil)
        wait(for: [started], timeout: UITests.Timeouts.fireAnimation)
    }

    private func releaseCleanup() {
        guard let cleanupRelease else { return }
        do {
            try Data().write(to: cleanupRelease)
        } catch {
            XCTFail("Unable to release pending Fire cleanup: \(error)")
        }
    }

    private func waitForBurnToFinish() {
        let path = cleanupRelease!.path + ".finished"
        let finished = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: path) }, evaluatedWith: nil)
        wait(for: [finished], timeout: UITests.Timeouts.fireAnimation)
    }
}
