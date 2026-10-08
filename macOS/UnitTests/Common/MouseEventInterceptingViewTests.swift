//
//  MouseEventInterceptingViewTests.swift
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

/// Since the macOS 27 SDK, a plain button handed its mouse-down from inside the event monitor never
/// fires, so buttons get their whole press from AppKit instead.
@MainActor
final class MouseEventInterceptingViewTests: XCTestCase {

    /// The interceptors share one press across tests, and only a mouse-down with a new timestamp ends it.
    private static var timestamp: TimeInterval = 0

    private var window: KeyWindow!
    private var sut: MouseBlockingBackgroundView!
    private var button: RecordingButton!
    private var plainView: RecordingView!

    override func setUp() {
        super.setUp()
        window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        sut = MouseBlockingBackgroundView()
        sut.frame = window.contentView!.bounds
        window.contentView!.addSubview(sut)
        sut.stopListening()

        button = RecordingButton(frame: NSRect(x: 20, y: 120, width: 100, height: 30))
        sut.addSubview(button)
        plainView = RecordingView(frame: NSRect(x: 20, y: 20, width: 100, height: 30))
        sut.addSubview(plainView)
    }

    override func tearDown() {
        window.close()
        window = nil
        sut = nil
        button = nil
        plainView = nil
        super.tearDown()
    }

    func testWhenAButtonIsPressedThenAppKitGetsTheWholePress() {
        XCTAssertNotNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: button)))
        XCTAssertNotNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDragged, over: button)))
        XCTAssertNotNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: button)))
        XCTAssertEqual(button.mouseDowns, 0)
    }

    /// Clicks have always focused what they hit, which is what draws a button's focus ring.
    func testWhenAButtonIsPressedThenItTakesFocus() {
        _ = sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: button))

        XCTAssertIdentical(window.firstResponder, button)
    }

    func testWhenAButtonPressEndsOverAnotherViewThenTheMouseUpStillGoesToAppKit() {
        _ = sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: button))

        XCTAssertNotNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDragged, over: plainView)))
        XCTAssertNotNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: plainView)))
        XCTAssertEqual(plainView.mouseUps, 0)
    }

    /// The text overlay sits above the panel's buttons, so a press can start in one and end in the other.
    func testWhenAButtonPressEndsOverAnotherInterceptorThenThatInterceptorLetsItThrough() {
        let overlay = MouseBlockingBackgroundView()
        overlay.frame = window.contentView!.bounds
        overlay.passthroughBottomHeight = 160
        window.contentView!.addSubview(overlay)
        overlay.stopListening()
        let textView = RecordingView(frame: NSRect(x: 20, y: 165, width: 100, height: 30))
        overlay.addSubview(textView)

        let mouseDown = mouseEvent(.leftMouseDown, over: button)
        XCTAssertNotNil(sut.handleMonitoredEvent(mouseDown))
        XCTAssertNotNil(overlay.handleMonitoredEvent(mouseDown))

        XCTAssertNotNil(overlay.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: textView)))
        XCTAssertEqual(textView.mouseUps, 0)
    }

    func testWhenAViewThatIsNotAButtonIsPressedThenTheClickIsForwardedAndConsumed() {
        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: plainView)))
        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: plainView)))

        XCTAssertEqual(plainView.mouseDowns, 1)
        XCTAssertEqual(plainView.mouseUps, 1)
    }

    /// A menu can swallow a button's mouse-up, so the next press decides on its own.
    func testWhenANewPressStartsAfterAButtonPressThenClicksElsewhereAreConsumedAgain() {
        _ = sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: button))

        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: plainView)))
        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: plainView)))
        XCTAssertEqual(plainView.mouseDowns, 1)
        XCTAssertEqual(plainView.mouseUps, 1)
    }

    private func mouseEvent(_ type: NSEvent.EventType, over view: NSView) -> NSEvent {
        Self.timestamp += 1
        let location = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: Self.timestamp,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                  clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }
}

private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

/// Counts a mouse-down handed over by hand instead of tracking it, which would block the test.
/// Takes focus whatever the Mac's keyboard navigation setting.
private final class RecordingButton: NSButton {
    private(set) var mouseDowns = 0

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { mouseDowns += 1 }
}

private final class RecordingView: NSView {
    private(set) var mouseDowns = 0
    private(set) var mouseUps = 0

    override func mouseDown(with event: NSEvent) { mouseDowns += 1 }
    override func mouseUp(with event: NSEvent) { mouseUps += 1 }
}
