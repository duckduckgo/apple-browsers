//
//  HoverTrackingAreaTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

/// https://app.asana.com/1/137249556945/project/1199230911884351/task/1208347387296425
@MainActor
final class HoverTrackingAreaTests: XCTestCase {

    private var window: ToggleableKeyWindow!
    private var sut: MouseOverView!

    override func setUp() {
        super.setUp()
        // place the window right under the real cursor so that the view is hovered by definition
        let mouseLocation = NSEvent.mouseLocation
        let frame = NSRect(x: mouseLocation.x - 100, y: mouseLocation.y - 100, width: 200, height: 200)
        window = ToggleableKeyWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false

        sut = MouseOverView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(sut)
    }

    override func tearDown() {
        window.orderOut(nil)
        window = nil
        sut = nil
        super.tearDown()
    }

    func testWhenViewIsInKeyWindowUnderCursorThenIsMouseOver() {
        window.setKey(true)
        sut.updateTrackingAreas()

        XCTAssertTrue(sut.isMouseOver)
    }

    /// `.activeInKeyWindow` tracking areas receive no `mouseExited` when the window resigns key (other app activated, menu shown…):
    /// the hover state used to stay stuck (the tab preview hid only on a hover change).
    func testWhenWindowResignsKeyWithCursorInsideThenMouseOverIsReset() {
        window.setKey(true)
        sut.updateTrackingAreas()
        XCTAssertTrue(sut.isMouseOver)

        window.setKey(false)

        XCTAssertFalse(sut.isMouseOver)
    }

    func testWhenWindowBecomesKeyWithCursorInsideThenMouseOverIsSet() {
        window.setKey(false)
        sut.updateTrackingAreas()
        XCTAssertFalse(sut.isMouseOver)

        window.setKey(true)

        XCTAssertTrue(sut.isMouseOver)
    }

    /// e.g. a tab opened in a background window with the cursor over it must not be hovered
    func testWhenViewIsUpdatedInNonKeyWindowThenIsNotMouseOver() {
        window.setKey(false)

        sut.updateTrackingAreas()

        XCTAssertFalse(sut.isMouseOver)
    }

    // MARK: - Event ordering (https://github.com/duckduckgo/apple-browsers/pull/489)

    /// AppKit may deliver `mouseEntered` after a newer `mouseExited`: the hover state must not stay stuck.
    func testWhenMouseEnteredIsDeliveredAfterNewerMouseExitedThenMouseOverIsReset() throws {
        window.setKey(true)
        sut.updateTrackingAreas()
        let trackingArea = try XCTUnwrap(sut.trackingAreas.compactMap { $0 as? HoverTrackingArea }.first)

        trackingArea.mouseExited(try makeEnterExitEvent(.mouseExited, timestamp: 2))
        XCTAssertFalse(sut.isMouseOver)

        // delayed event with older timestamp
        trackingArea.mouseEntered(try makeEnterExitEvent(.mouseEntered, timestamp: 1))

        let reset = expectation(description: "mouse over reset")
        DispatchQueue.main.async { DispatchQueue.main.async { reset.fulfill() } }
        wait(for: [reset], timeout: 2)
        XCTAssertFalse(sut.isMouseOver)
    }

    // MARK: - Subviews

    /// `mouseExited` of a subview (close button etc.) bubbles up the responder chain but must not reset the hover state of its superview.
    func testWhenSubviewReportsMouseExitedThenSuperviewStaysMouseOver() throws {
        let subview = MouseOverView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        sut.addSubview(subview)
        window.setKey(true)
        sut.updateTrackingAreas()
        subview.updateTrackingAreas()
        XCTAssertTrue(sut.isMouseOver)
        let subviewTrackingArea = try XCTUnwrap(subview.trackingAreas.compactMap { $0 as? HoverTrackingArea }.first)

        subviewTrackingArea.mouseExited(try makeEnterExitEvent(.mouseExited, timestamp: 1))

        XCTAssertFalse(subview.isMouseOver)
        XCTAssertTrue(sut.isMouseOver)
    }

    private func makeEnterExitEvent(_ type: NSEvent.EventType, timestamp: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type,
                                             location: NSPoint(x: 10, y: 10),
                                             modifierFlags: [],
                                             timestamp: timestamp,
                                             windowNumber: window.windowNumber,
                                             context: nil,
                                             eventNumber: 0,
                                             trackingNumber: 0,
                                             userData: nil))
    }

}

final class ToggleableKeyWindow: NSWindow {

    private var isKey = false
    override var isKeyWindow: Bool { isKey }

    func setKey(_ isKey: Bool) {
        self.isKey = isKey
        let name = isKey ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification
        NotificationCenter.default.post(name: name, object: self)
    }

}
