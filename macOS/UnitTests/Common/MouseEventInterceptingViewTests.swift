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

@MainActor
final class MouseEventInterceptingViewTests: XCTestCase {

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

    func testWhenAButtonPressEndsOverAnotherInterceptorThenThatInterceptorLetsItThrough() {
        let (overlay, textView) = addTextOverlay()

        let mouseDown = mouseEvent(.leftMouseDown, over: button)
        _ = sut.handleMonitoredEvent(mouseDown)
        _ = overlay.handleMonitoredEvent(mouseDown)

        XCTAssertNotNil(overlay.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: textView)))
        XCTAssertEqual(textView.mouseUps, 0)
    }

    func testWhenAPressStartsOnAViewAboveThePanelThenItsMouseUpOverThePanelGoesToAppKit() {
        let buttonAbove = NSButton(frame: NSRect(x: 180, y: 120, width: 100, height: 30))
        window.contentView!.addSubview(buttonAbove)

        XCTAssertNotNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: buttonAbove)))
        XCTAssertNotNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: plainView)))
        XCTAssertEqual(plainView.mouseUps, 0)
    }

    func testWhenAViewThatIsNotAButtonIsPressedThenTheClickIsForwardedAndConsumed() {
        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: plainView)))
        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: plainView)))

        XCTAssertEqual(plainView.mouseDowns, 1)
        XCTAssertEqual(plainView.mouseUps, 1)
    }

    func testWhenAPressThePanelTookEndsOverAnotherInterceptorThenThePanelStillConsumesIt() {
        let (overlay, textView) = addTextOverlay()

        let mouseDown = mouseEvent(.leftMouseDown, over: plainView)
        _ = sut.handleMonitoredEvent(mouseDown)
        _ = overlay.handleMonitoredEvent(mouseDown)

        let mouseUp = mouseEvent(.leftMouseUp, over: textView)
        XCTAssertNotNil(overlay.handleMonitoredEvent(mouseUp))
        XCTAssertNil(sut.handleMonitoredEvent(mouseUp))
        XCTAssertEqual(textView.mouseUps, 0)
    }

    func testWhenANewPressStartsAfterAButtonPressThenClicksElsewhereAreConsumedAgain() {
        _ = sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: button))

        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseDown, over: plainView)))
        XCTAssertNil(sut.handleMonitoredEvent(mouseEvent(.leftMouseUp, over: plainView)))
        XCTAssertEqual(plainView.mouseDowns, 1)
        XCTAssertEqual(plainView.mouseUps, 1)
    }

    private func addTextOverlay() -> (MouseBlockingBackgroundView, RecordingView) {
        let overlay = MouseBlockingBackgroundView()
        overlay.frame = window.contentView!.bounds
        overlay.passthroughBottomHeight = 160
        window.contentView!.addSubview(overlay)
        overlay.stopListening()
        let textView = RecordingView(frame: NSRect(x: 20, y: 165, width: 100, height: 30))
        overlay.addSubview(textView)
        return (overlay, textView)
    }

    private func mouseEvent(_ type: NSEvent.EventType, over view: NSView) -> NSEvent {
        let location = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                  clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }
}

private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

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
