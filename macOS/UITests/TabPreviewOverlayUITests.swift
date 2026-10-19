//
//  TabPreviewOverlayUITests.swift
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

import AppKit
import XCTest

/// https://app.asana.com/1/137249556945/project/1199230911884351/task/1208347387296425
/// A window of another process that doesn‘t activate (like a system notification) taking the mouse
/// must not leave the tab preview stuck.
final class TabPreviewOverlayUITests: UITestCase {

    private var overlay: OverlayPanel?

    override func setUpWithError() throws {
        try super.setUpWithError()
        // exposes the tab preview window to accessibility
        app = XCUIApplication.setUp(featureFlags: ["tabPreviewAccessibilityForUITests": true])
        app.openNewWindow()
    }

    override func tearDown() {
        overlay?.orderOut(nil)
        overlay = nil
        super.tearDown()
    }

    func testTabPreviewAndHighlightAreCleared_whenNonActivatingWindowReceivesMouseAndMouseMovesDownFromTheTab() throws {
        app.openNewTab()
        app.openNewTab()
        let inactiveTab = tabs.element(boundBy: 0)
        XCTAssertTrue(inactiveTab.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(inactiveTab.isSelected)

        // hover the inactive tab until the preview is shown: the tab is highlighted
        inactiveTab.hover()
        let preview = app.windows[XCUIApplication.AccessibilityIdentifiers.tabPreviewWindow]
        XCTAssertTrue(preview.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Tab preview should be shown")
        XCTAssertEqual(inactiveTab.placeholderValue, "hovered", "The tab should be highlighted")

        // a non-activating window of another process appears under the cursor and receives the mouse clicks (like a system notification)
        let overlay = showNonActivatingOverlayUnderCursor()

        // the overlay took the mouse from the tab: the preview is hidden and the highlight is removed right away
        assertPreviewHidden(preview, andHighlightRemovedFrom: inactiveTab, "when the overlay appears")
        // the overlay is another process‘ window: let it process the events (the test runner doesn‘t run the application event loop)
        let tabCenter = inactiveTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        tabCenter.click()
        pumpEvents(for: 0.5)
        XCTAssertEqual(overlay.clicksCount, 1, "The overlay should be receiving the mouse clicks")

        // move the mouse down from the tab area
        tabCenter.withOffset(CGVector(dx: 0, dy: 150)).hover()
        pumpEvents(for: 0.5)

        assertPreviewHidden(preview, andHighlightRemovedFrom: inactiveTab, "when the mouse moves down from the tab")
    }

    private func assertPreviewHidden(_ preview: XCUIElement, andHighlightRemovedFrom tab: XCUIElement, _ moment: String, file: StaticString = #filePath, line: UInt = #line) {
        let previewHidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: preview)
        XCTAssertEqual(XCTWaiter().wait(for: [previewHidden], timeout: UITests.Timeouts.elementExistence), .completed, "Tab preview should be hidden \(moment)", file: file, line: line)
        let highlightRemoved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "placeholderValue == 'idle'"), object: tab)
        XCTAssertEqual(XCTWaiter().wait(for: [highlightRemoved], timeout: UITests.Timeouts.elementExistence), .completed, "Tab highlight should be removed \(moment)", file: file, line: line)
    }

    /// The test runner doesn‘t run the `NSApplication` event loop: dispatch the window events manually
    private func pumpEvents(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            guard let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) else { continue }
            NSApp.sendEvent(event)
        }
    }

    /// Tabs of the main window: once the preview is shown, `app.windows.firstMatch` may be the preview window
    private var tabs: XCUIElementQuery {
        app.windows.containing(.tabGroup, identifier: "TabBarViewController.CollectionView").firstMatch.tabs
    }

    /// Shows a borderless non-activating panel (this test runner is another process than the app) over the mouse cursor
    @discardableResult
    private func showNonActivatingOverlayUnderCursor() -> OverlayPanel {
        _ = NSApplication.shared
        let mouse = NSEvent.mouseLocation
        let panel = OverlayPanel(contentRect: NSRect(x: mouse.x - 60, y: mouse.y - 60, width: 120, height: 120),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = NSColor.systemRed.withAlphaComponent(0.4)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        overlay = panel
        // let the window server deliver the resulting mouse events
        pumpEvents(for: 0.5)
        return panel
    }

}

/// Non-activating panel counting mouse clicks it receives
private final class OverlayPanel: NSPanel {

    private(set) var clicksCount = 0

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { clicksCount += 1 }
        super.sendEvent(event)
    }

}
