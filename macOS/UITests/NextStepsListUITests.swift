//
//  NextStepsListUITests.swift
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

import Utilities
import XCTest

final class NextStepsListUITests: UITestCase {

    private var webView: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["nextStepsListWidget": true])
        app.enforceSingleWindow()
        resetNextSteps()
        webView = app.webViews.firstMatch
    }

    override func tearDown() {
        webView = nil
        app = nil
        super.tearDown()
    }

    func testNextStepsListWidgetAppearsOnNewTabPage() throws {
        app.openNewTab()

        // Confirm Next Steps widget is visible (same section label is used for legacy and list widget)
        XCTAssertTrue(nextStepsSection.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Next Steps content should be visible on New Tab Page")

        // Confirm card for Next Steps List widget is visible, using its "No Thanks" button
        XCTAssertTrue(nextStepsCardDismissButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Dismiss button should be visible in the Next Steps content")
    }

    func testNextStepsCardDisappearsAfterDismissal() throws {
        app.openNewTab()

        // Confirm first Next Steps card is visible, using its CTA button
        XCTAssertTrue(nextStepsFirstCardCTAButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "First card in Next Steps List should be visible on New Tab Page")

        nextStepsCardDismissButton.tap()

        // Confirm first Next Steps card is dismissed
        XCTAssertTrue(nextStepsFirstCardCTAButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "First card in Next Steps List should be dismissed after tapping dismiss button")
    }

    func testNextStepsListWidgetDisappearsAfterMaxDemonstrationDays() throws {
        shiftMaxNextStepsDays()
        app.openNewTab()

        // Confirm Next Steps widget is not visible
        XCTAssertTrue(nextStepsSection.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
                      "Next Steps content should not be visible after max demonstration days")
    }
}

// MARK: - Test helpers

private extension NextStepsListUITests {

    var newTabPageSubmenu: XCUIElement {
        app.debugMenu.menuItems[AccessibilityIdentifiers.NewTabPage.newTabPageDebugMenu]
    }

    var resetNextStepsMenuItem: XCUIElement {
        newTabPageSubmenu.menuItems[AccessibilityIdentifiers.NewTabPage.resetNextStepsMenuItem]
    }

    var shiftMaxDaysMenuItem: XCUIElement {
        newTabPageSubmenu.menuItems[AccessibilityIdentifiers.NewTabPage.shiftMaxDaysMenuItem]
    }

    var nextStepsSection: XCUIElement {
        webView.staticTexts["Next Steps"]
    }

    var nextStepsFirstCardCTAButton: XCUIElement {
        webView.buttons["Try Duck Player"]
    }

    var nextStepsCardDismissButton: XCUIElement {
        webView.buttons["No Thanks"]
    }

    func resetNextSteps() {
        resetNextStepsMenuItem.clickAfterExistenceTestSucceeds()
    }

    func shiftMaxNextStepsDays() {
        shiftMaxDaysMenuItem.clickAfterExistenceTestSucceeds()
    }
}
