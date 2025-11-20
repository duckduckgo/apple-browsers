//
//  DefaultBrowserAndDockPromptsUITests.swift
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

final class DefaultBrowserAndDockPromptsUITests: UITestCase {

    private var webView: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()
        webView = app.webViews.firstMatch
    }

    override func tearDown() {
        webView = nil
        app = nil
        super.tearDown()
    }

    func testExample() throws {
        app.simulateFreshAppInstall()
    }
}

// MARK: - Helper Identifiers

private extension XCUIApplication {
    enum AccessibilityIdentifiers {
        static let simulateFreshAppInstallMenuItem = "DefaultBrowserAndDockPromptDebugMenu.simulateFreshInstall"
        static let overrideCurrentDateMenuItem = "DefaultBrowserAndDockPromptDebugMenu.simulateCurrentDate"
    }

    var simulateFreshAppInstallMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.simulateFreshAppInstallMenuItem]
    }

    var overrideCurrentDateMenuItem: XCUIElement {
        menuItems[AccessibilityIdentifiers.overrideCurrentDateMenuItem]
    }
}

// MARK: - Helper Methods

private extension XCUIApplication {

    /// Open Debug menu -> Default Browser and Dock Prompt submenu -> Simulate Fresh App Install
    func simulateFreshAppInstall() {
        let debugMenu = menuBars.menuBarItems["Debug"]
        debugMenu.click()

        let defaultBrowserAndDockPromptSubmenu = menuItems["SAD/ATT Prompts"]
        XCTAssertTrue(defaultBrowserAndDockPromptSubmenu.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Default Browser and Dock Prompt submenu should exist")
        defaultBrowserAndDockPromptSubmenu.hover()

        XCTAssertTrue(simulateFreshAppInstallMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Simulate Fresh App Install menu item should exist")
        simulateFreshAppInstallMenuItem.click()
    }
}
