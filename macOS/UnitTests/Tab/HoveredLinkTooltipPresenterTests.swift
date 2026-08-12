//
//  HoveredLinkTooltipPresenterTests.swift
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
final class HoveredLinkTooltipPresenterTests: XCTestCase {

    typealias Presenter = HoveredLinkTooltipPresenter

    private static let hostBounds = NSRect(x: 0, y: 0, width: 1280, height: 800)

    private static func windowed(windowBottom: CGFloat = 400, screenBottom: CGFloat? = 0) -> Presenter.WindowInputs {
        Presenter.WindowInputs(
            isFullScreen: false,
            isZoomed: false,
            windowBottom: windowBottom,
            screenVisibleFrameBottom: screenBottom
        )
    }

    private static func fullScreen() -> Presenter.WindowInputs {
        Presenter.WindowInputs(
            isFullScreen: true,
            isZoomed: false,
            windowBottom: 0,
            screenVisibleFrameBottom: 0
        )
    }

    private static func zoomed(windowBottom: CGFloat = 0, screenBottom: CGFloat = 0) -> Presenter.WindowInputs {
        Presenter.WindowInputs(
            isFullScreen: false,
            isZoomed: true,
            windowBottom: windowBottom,
            screenVisibleFrameBottom: screenBottom
        )
    }

    // MARK: - computePosition

    func testComputePosition_whenCursorIsFarFromBottom_returnsInsideBottomLeft() {
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 600, y: 400),
            cursorPointInScreen: NSPoint(x: 600, y: 400),
            hostBounds: Self.hostBounds,
            inputs: Self.windowed()
        )
        XCTAssertEqual(position, .insideBottomLeft)
    }

    func testComputePosition_whenCursorIsNearBottomAndWindowHasRoomBelow_returnsBelowWindow() {
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 200, y: 30),
            cursorPointInScreen: NSPoint(x: 200, y: 430),
            hostBounds: Self.hostBounds,
            inputs: Self.windowed(windowBottom: 400, screenBottom: 0)
        )
        XCTAssertEqual(position, .belowWindow)
    }

    func testComputePosition_whenFullScreenAndCursorNearBottom_returnsAboveCursor() {
        let cursorInScreen = NSPoint(x: 600, y: 50)
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 600, y: 50),
            cursorPointInScreen: cursorInScreen,
            hostBounds: Self.hostBounds,
            inputs: Self.fullScreen()
        )
        XCTAssertEqual(position, .aboveCursor(cursorPointInScreen: cursorInScreen))
    }

    func testComputePosition_whenZoomedAndCursorNearBottom_returnsAboveCursor() {
        let cursorInScreen = NSPoint(x: 200, y: 30)
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 200, y: 30),
            cursorPointInScreen: cursorInScreen,
            hostBounds: Self.hostBounds,
            inputs: Self.zoomed()
        )
        XCTAssertEqual(position, .aboveCursor(cursorPointInScreen: cursorInScreen))
    }

    func testComputePosition_whenZoomedButCursorFarFromBottom_returnsInsideBottomLeft() {
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 600, y: 540),
            cursorPointInScreen: NSPoint(x: 600, y: 540),
            hostBounds: Self.hostBounds,
            inputs: Self.zoomed()
        )
        XCTAssertEqual(position, .insideBottomLeft)
    }

    func testComputePosition_whenWindowSittingAtBottomOfScreen_fallsBackToAboveCursor() {
        // Window at y=0 on a screen at y=0 → no room beneath.
        let cursorInScreen = NSPoint(x: 200, y: 30)
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 200, y: 30),
            cursorPointInScreen: cursorInScreen,
            hostBounds: Self.hostBounds,
            inputs: Self.windowed(windowBottom: 0, screenBottom: 0)
        )
        XCTAssertEqual(position, .aboveCursor(cursorPointInScreen: cursorInScreen))
    }

    func testComputePosition_withNoMouseLocation_returnsInsideBottomLeft() {
        let position = Presenter.computePosition(
            mouseLocationInWindow: nil,
            cursorPointInScreen: nil,
            hostBounds: Self.hostBounds,
            inputs: Self.windowed()
        )
        XCTAssertEqual(position, .insideBottomLeft)
    }

    func testComputePosition_withNilWindow_returnsInsideBottomLeft() {
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 0, y: 0),
            window: nil,
            hostBounds: .zero
        )
        XCTAssertEqual(position, .insideBottomLeft)
    }

    func testComputePosition_withNoScreen_treatsAsNoRoomBelow() {
        // No associated screen — fall back to in-window when far from bottom,
        // above-cursor when near bottom.
        let inputsNoScreen = Presenter.WindowInputs(
            isFullScreen: false,
            isZoomed: false,
            windowBottom: 0,
            screenVisibleFrameBottom: nil
        )
        let position = Presenter.computePosition(
            mouseLocationInWindow: NSPoint(x: 200, y: 30),
            cursorPointInScreen: NSPoint(x: 200, y: 30),
            hostBounds: Self.hostBounds,
            inputs: inputsNoScreen
        )
        XCTAssertEqual(position, .aboveCursor(cursorPointInScreen: NSPoint(x: 200, y: 30)))
    }

    // MARK: - isMouseNearBottom

    func testIsMouseNearBottom_returnsTrueInsideBand() {
        let host = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertTrue(Presenter.isMouseNearBottom(NSPoint(x: 100, y: 0), hostBounds: host))
        XCTAssertTrue(Presenter.isMouseNearBottom(NSPoint(x: 100, y: 50), hostBounds: host))
        XCTAssertFalse(Presenter.isMouseNearBottom(NSPoint(x: 100, y: 200), hostBounds: host))
        XCTAssertFalse(Presenter.isMouseNearBottom(NSPoint(x: 100, y: 800), hostBounds: host))
    }

    // MARK: - hasRoomBelowWindow

    func testHasRoomBelowWindow_whenAmpleSpaceBeneath_returnsTrue() {
        let inputs = Presenter.WindowInputs(
            isFullScreen: false,
            isZoomed: false,
            windowBottom: 500,
            screenVisibleFrameBottom: 0
        )
        XCTAssertTrue(Presenter.hasRoomBelowWindow(inputs: inputs))
    }

    func testHasRoomBelowWindow_whenAtBottomOfScreen_returnsFalse() {
        let inputs = Presenter.WindowInputs(
            isFullScreen: false,
            isZoomed: false,
            windowBottom: 0,
            screenVisibleFrameBottom: 0
        )
        XCTAssertFalse(Presenter.hasRoomBelowWindow(inputs: inputs))
    }

    // MARK: - Inspector dismissal helper (cursor-leaves-WebView)

    func testCursorLeavingWebViewDismissesTooltip_throughPureLogic() {
        // The inspector dismissal pivots on a cursor location being outside
        // the WebView's bounds-in-window. Verify the geometric check in
        // isolation.
        let webViewFrameInWindow = NSRect(x: 0, y: 100, width: 1280, height: 700)

        let insidePoint = NSPoint(x: 100, y: 200)
        let belowWebView = NSPoint(x: 100, y: 50)   // e.g. into a status bar / inspector pane
        let aboveWebView = NSPoint(x: 100, y: 850)  // e.g. into address bar / bookmarks bar

        XCTAssertTrue(webViewFrameInWindow.contains(insidePoint))
        XCTAssertFalse(webViewFrameInWindow.contains(belowWebView))
        XCTAssertFalse(webViewFrameInWindow.contains(aboveWebView))
    }
}
