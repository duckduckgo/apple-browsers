//
//  PromptBarMenuBarControllerTests.swift
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

/// Detached stand-in: a real `NSStatusBar` item presents an `NSStatusBarWindow`,
/// which unit tests are not allowed to do.
@MainActor
private final class MockPromptBarStatusItem: PromptBarStatusItem {
    let button: NSStatusBarButton? = NSStatusBarButton()
    var isVisible: Bool = true
}

final class PromptBarMenuBarControllerTests: XCTestCase {

    @MainActor
    func testWhenInitializedThenButtonShowsTemplateGlyph() {
        let statusItem = MockPromptBarStatusItem()

        _ = PromptBarMenuBarController(statusItem: statusItem)

        XCTAssertNotNil(statusItem.button?.image)
        XCTAssertEqual(statusItem.button?.image?.isTemplate, true)
    }

    @MainActor
    func testWhenHideThenStatusItemIsNotVisible() {
        let statusItem = MockPromptBarStatusItem()
        let controller = PromptBarMenuBarController(statusItem: statusItem)

        controller.hide()

        XCTAssertFalse(statusItem.isVisible)
    }

    @MainActor
    func testWhenShowThenStatusItemIsVisible() {
        let statusItem = MockPromptBarStatusItem()
        let controller = PromptBarMenuBarController(statusItem: statusItem)

        controller.hide()
        controller.show()

        XCTAssertTrue(statusItem.isVisible)
    }
}
