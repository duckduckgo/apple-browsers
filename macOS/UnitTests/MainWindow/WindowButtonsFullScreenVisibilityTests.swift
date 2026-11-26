//
//  WindowButtonsFullScreenVisibilityTests.swift
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
final class WindowButtonsFullScreenVisibilityTests: XCTestCase {

    /// Reports `.fullScreen` in its style mask without going through the full screen transition.
    private final class FullScreenTestWindow: NSWindow {
        var reportsFullScreen = false

        override var styleMask: NSWindow.StyleMask {
            get { reportsFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
            set { super.styleMask = newValue }
        }
    }

    private var window: FullScreenTestWindow!

    override func setUp() async throws {
        window = FullScreenTestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                      backing: .buffered,
                                      defer: true)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() async throws {
        window.close()
        window = nil
    }

    private var buttons: [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    private var ancestors: [NSView] {
        var result = [NSView]()
        var view = window.standardWindowButton(.closeButton)?.superview
        while let current = view, current.superview != nil {
            result.append(current)
            view = current.superview
        }
        return result
    }

    private var rootView: NSView? {
        window.contentView?.superview
    }

    /// Hides the buttons and their ancestor chain the way AppKit leaves them on macOS 27 in full screen.
    private func hideButtonsAndAncestors() throws {
        XCTAssertEqual(buttons.count, 3)
        XCTAssertFalse(ancestors.isEmpty)
        let root = try XCTUnwrap(rootView)
        XCTAssertFalse(ancestors.contains { $0 === root })

        for button in buttons {
            button.alphaValue = 0
            button.isHidden = true
        }
        for ancestor in ancestors {
            ancestor.alphaValue = 0
            ancestor.isHidden = true
        }
        root.alphaValue = 0.5
    }

    func testWhenWindowIsInFullScreenThenButtonsAndAncestorsAreShownOnMacOS27() throws {
        try hideButtonsAndAncestors()
        window.reportsFullScreen = true

        window.forceWindowButtonsVisibleInFullScreen()

        if #available(macOS 27, *) {
            for view in buttons + ancestors {
                XCTAssertEqual(view.alphaValue, 1, "\(view.className)")
                XCTAssertFalse(view.isHidden, "\(view.className)")
            }
        } else {
            for view in buttons + ancestors {
                XCTAssertEqual(view.alphaValue, 0, "\(view.className)")
                XCTAssertTrue(view.isHidden, "\(view.className)")
            }
        }
        XCTAssertEqual(rootView?.alphaValue, 0.5, "The window's root view must not be changed")
    }

    func testWhenWindowIsNotInFullScreenThenNothingChanges() throws {
        try hideButtonsAndAncestors()
        window.reportsFullScreen = false

        window.forceWindowButtonsVisibleInFullScreen()

        for view in buttons + ancestors {
            XCTAssertEqual(view.alphaValue, 0, "\(view.className)")
            XCTAssertTrue(view.isHidden, "\(view.className)")
        }
        XCTAssertEqual(rootView?.alphaValue, 0.5)
    }

}
