//
//  ToolbarHandlerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
@testable import DuckDuckGo

// MARK: - ToolbarHandlerTests

class ToolbarHandlerTests: XCTestCase {

    var toolbarHandler: ToolbarHandler!
    var mockToolbar: BrowserToolbarView!
    var mockNavigatable: MockNavigatable!

    override func setUp() {
        super.setUp()
        mockToolbar = BrowserToolbarView()
        mockNavigatable = MockNavigatable(canGoBack: true, canGoForward: false)
        toolbarHandler = ToolbarHandler(toolbar: mockToolbar)
    }

    override func tearDown() {
        toolbarHandler = nil
        mockToolbar = nil
        mockNavigatable = nil
        super.tearDown()
    }
    
    func testUpdateToolbarWithStateNewTab() {
        // To prevent assertion for using experimental colors with the default theme
        toolbarHandler.updateToolbarWithState(.newTab)

        let items = mockToolbar.arrangedToolbarButtonViews.compactMap { $0 as? BrowserChromeButton }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[0].accessibilityLabel, UserText.actionOpenBookmarks)
        XCTAssertEqual(items[1].accessibilityLabel, UserText.actionOpenPasswords)
        XCTAssertEqual(items[2].accessibilityLabel, UserText.actionForgetAll)
        XCTAssertEqual(items[3].accessibilityLabel, UserText.tabSwitcherAccessibilityLabel)
        XCTAssertEqual(items[4].accessibilityLabel, UserText.menuButtonHint)
    }

    func testUpdateToolbarWithStatePageLoaded() {
        // To prevent assertion for using experimental colors with the default theme
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))

        let items = mockToolbar.arrangedToolbarButtonViews.compactMap { $0 as? BrowserChromeButton }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[0].accessibilityLabel, UserText.keyCommandBrowserBack)
        XCTAssertEqual(items[1].accessibilityLabel, UserText.keyCommandBrowserForward)
        XCTAssertEqual(items[2].accessibilityLabel, UserText.actionForgetAll)
        XCTAssertEqual(items[3].accessibilityLabel, UserText.tabSwitcherAccessibilityLabel)
        XCTAssertEqual(items[4].accessibilityLabel, UserText.menuButtonHint)

        XCTAssertTrue(toolbarHandler.backButton.isEnabled)
        XCTAssertFalse(toolbarHandler.forwardButton.isEnabled)
    }

    func testUpdateToolbarWithStateNoChange() {
        toolbarHandler.updateToolbarWithState(.newTab)
        let initialItems = mockToolbar.arrangedToolbarButtonViews

        toolbarHandler.updateToolbarWithState(.newTab)

        XCTAssertEqual(mockToolbar.arrangedToolbarButtonViews, initialItems)
    }

    func testBackButtonEnabledState() {
        mockNavigatable = MockNavigatable(canGoBack: true, canGoForward: false)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertTrue(toolbarHandler.backButton.isEnabled)

        mockNavigatable = MockNavigatable(canGoBack: false, canGoForward: false)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertFalse(toolbarHandler.backButton.isEnabled)
    }

    func testForwardButtonEnabledState() {
        mockNavigatable = MockNavigatable(canGoBack: false, canGoForward: true)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertTrue(toolbarHandler.forwardButton.isEnabled)

        mockNavigatable = MockNavigatable(canGoBack: false, canGoForward: false)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertFalse(toolbarHandler.forwardButton.isEnabled)
    }
}

// MARK: - MockNavigatable

final class MockNavigatable: Navigatable {
    var canGoBack: Bool
    var canGoForward: Bool

    init(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}
