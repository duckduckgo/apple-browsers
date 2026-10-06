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

@MainActor
private final class StatusItemFactory {
    let item = MockPromptBarStatusItem()
    private(set) var createdCount = 0

    func make() -> PromptBarStatusItem {
        createdCount += 1
        return item
    }
}

final class PromptBarMenuBarControllerTests: XCTestCase {

    @MainActor
    func testWhenInitializedThenStatusItemIsNotCreated() {
        let factory = StatusItemFactory()

        _ = PromptBarMenuBarController(makeStatusItem: factory.make)

        XCTAssertEqual(factory.createdCount, 0)
    }

    @MainActor
    func testWhenHiddenBeforeBeingShownThenStatusItemIsNotCreated() {
        let factory = StatusItemFactory()
        let controller = PromptBarMenuBarController(makeStatusItem: factory.make)

        controller.hide()

        XCTAssertEqual(factory.createdCount, 0)
    }

    @MainActor
    func testWhenShownThenButtonShowsTemplateGlyph() {
        let factory = StatusItemFactory()
        let controller = PromptBarMenuBarController(makeStatusItem: factory.make)

        controller.show()

        XCTAssertNotNil(factory.item.button?.image)
        XCTAssertEqual(factory.item.button?.image?.isTemplate, true)
    }

    @MainActor
    func testWhenShownThenStatusItemIsVisible() {
        let factory = StatusItemFactory()
        let controller = PromptBarMenuBarController(makeStatusItem: factory.make)

        controller.show()

        XCTAssertEqual(factory.createdCount, 1)
        XCTAssertTrue(factory.item.isVisible)
    }

    @MainActor
    func testWhenHiddenAfterBeingShownThenStatusItemIsNotVisible() {
        let factory = StatusItemFactory()
        let controller = PromptBarMenuBarController(makeStatusItem: factory.make)

        controller.show()
        controller.hide()

        XCTAssertFalse(factory.item.isVisible)
    }

    @MainActor
    func testWhenShownTwiceThenStatusItemIsCreatedOnce() {
        let factory = StatusItemFactory()
        let controller = PromptBarMenuBarController(makeStatusItem: factory.make)

        controller.show()
        controller.show()

        XCTAssertEqual(factory.createdCount, 1)
    }
}
