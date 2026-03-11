//
//  PromoQueueUITests.swift
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

import XCTest
import Utilities

final class PromoQueueUITests: UITestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp(featureFlags: ["promoQueue": true])
        app.enforceSingleWindow()
        app.resetPromoState()
        app.dismissNextSteps()
    }

    override func tearDown() {
        app.closePromoIfNeeded()
        app = nil
        super.tearDown()
    }

    func testWhenNoneResult_ThenSamePromoReshows() throws {
        app.fireTestTrigger()
        XCTAssertTrue(app.alertA.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a alert should appear")

        app.alertA.noneButton.click()
        XCTAssertTrue(app.alertA.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a should dismiss after None")

        app.fireTestTrigger()
        XCTAssertTrue(app.alertA.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a should show again after None")
    }

    func testWhenEligibilityLost_ThenNextPromoShows() throws {
        app.fireTestTrigger()
        XCTAssertTrue(app.alertA.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a should appear")
        app.alertA.setIneligibleButton.click()
        XCTAssertTrue(app.alertA.waitForNonExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a should hide after Set Ineligible")

        app.fireTestTrigger()
        XCTAssertTrue(app.alertB.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-b should appear when promo-a is ineligible")
    }

    func testWhenCooldownActive_ThenPromosBlocked() throws {
        app.fireTestTrigger()
        app.alertA.dismissWithCooldownButton.clickAfterExistenceTestSucceeds()
        XCTAssertTrue(app.alertA.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))

        // Promo A on cooldown for 1 day, other user-initiated promos (e.g. Promo B) on cooldown for 1 hour
        // Promo C is app-initiated and can be shown
        app.fireTestTrigger()
        XCTAssertTrue(app.alertC.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-c should show when user-initiated promo (promo-a) is on cooldown")
        app.alertC.dismissWithCooldownButton.click()
        XCTAssertTrue(app.alertC.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))

        // All promos on cooldown
        app.fireTestTrigger()
        XCTAssertFalse(app.dialogs.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence), "No promo should show when cooldowns block all")
    }

    func testWhenDateAdvanced_ThenCooldownsUnblocked() throws {
        app.fireTestTrigger()
        app.alertA.dismissWithCooldownButton.clickAfterExistenceTestSucceeds()
        XCTAssertTrue(app.alertA.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))

        // Promo A on cooldown for 1 day, other user-initiated promos (e.g. Promo B) on cooldown for 1 hour
        // Advance by 1 hour to trigger Promo B
        app.advanceSimulatedDateByHour()
        app.fireTestTrigger()
        XCTAssertTrue(app.alertB.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-b should show after 1h (global cooldown elapsed)")

        app.alertB.actionButton.click()
        XCTAssertTrue(app.alertB.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))

        // Promo A on cooldown for 1 day
        // Advance by 1 day to trigger Promo A
        app.advanceSimulatedDateByDay()
        app.fireTestTrigger()
        XCTAssertTrue(app.alertA.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a should show after 1 day (personal cooldown elapsed)")
    }

    func testWhenShownAtShutdown_ThenRestoredAndPermanentDismissalSuppresses() throws {
        app.fireTestTrigger()
        XCTAssertTrue(app.alertA.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        app.terminate()
        app.launch()

        XCTAssertTrue(app.alertA.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a should restore on relaunch (lastShown > lastDismissed)")

        app.alertA.dismissPermanentlyButton.click()
        XCTAssertTrue(app.alertA.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))

        app.fireTestTrigger()
        XCTAssertFalse(app.alertA.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-a should not show after permanent dismissal")
    }

    func testWhenShownWithTimeout_ThenHiddenAfterTimeoutIntervalAndTimeoutResultRespected() throws {
        for promo in [app.alertA, app.alertB, app.alertC] {
            app.fireTestTrigger()
            promo.setIneligibleButton.clickAfterExistenceTestSucceeds()
        }

        app.fireTestTrigger()
        XCTAssertTrue(app.alertD.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Promo D is configured to auto-dismiss after 3 seconds with permanent dismissal
        XCTAssertTrue(app.alertD.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))

        app.fireTestTrigger()
        XCTAssertFalse(app.alertD.waitForExistence(timeout: UITests.Timeouts.elementExistence), "test-promo-d should not show after timeout")
    }
}

// MARK: - XCUIApplication Promo Queue Helpers

private extension XCUIApplication {
    private typealias Identifiers = Utilities.AccessibilityIdentifiers.PromoQueue

    var promoQueueMenu: XCUIElement {
        debugMenu.menuItems[Identifiers.promoQueueDebugMenu]
    }

    func fireTestTrigger() {
        typeKey("t", modifierFlags: [.command, .shift, .option, .control])
    }

    func closePromoIfNeeded() {
        guard sheets.firstMatch.exists else { return }
        sheets.firstMatch.noneButton.click()
    }

    func resetPromoState() {
        closePromoIfNeeded()
        openPromoQueueMenu()
        promoQueueMenu.menuItems[Identifiers.resetAllPromoState].clickAfterExistenceTestSucceeds()
    }

    func advanceSimulatedDateByHour() {
        openPromoQueueMenu()
        promoQueueMenu.menuItems[Identifiers.advanceSimulatedDate1Hour].clickAfterExistenceTestSucceeds()
    }

    func advanceSimulatedDateByDay() {
        openPromoQueueMenu()
        promoQueueMenu.menuItems[Identifiers.advanceSimulatedDate1Day].clickAfterExistenceTestSucceeds()
    }

    /// Dismisses Next Steps (external promo) and advances date to remove its cooldown,
    /// so test promos can be reliably triggered for each scenario.
    func dismissNextSteps() {
        guard nextSteps.exists else { return }
        debugMenu
            .menuItems[Utilities.AccessibilityIdentifiers.NewTabPage.newTabPageDebugMenu]
            .menuItems[Utilities.AccessibilityIdentifiers.NewTabPage.shiftMaxDaysMenuItem]
            .clickAfterExistenceTestSucceeds()
        advanceSimulatedDateByDay()
    }

    private func openPromoQueueMenu() {
        debugMenu.click()
        promoQueueMenu.hover()
    }

    var alertA: XCUIElement {
        sheets[Identifiers.testPromoAlert("test-promo-a")]
    }

    var alertB: XCUIElement {
        sheets[Identifiers.testPromoAlert("test-promo-b")]
    }

    var alertC: XCUIElement {
        sheets[Identifiers.testPromoAlert("test-promo-c")]
    }

    var alertD: XCUIElement {
        sheets[Identifiers.testPromoAlert("test-promo-d")]
    }
}

private extension XCUIElement {
    var noneButton: XCUIElement {
        buttons["None"]
    }

    var setIneligibleButton: XCUIElement {
        buttons["Set Ineligible"]
    }

    var dismissWithCooldownButton: XCUIElement {
        buttons["Dismiss (1 day cooldown)"]
    }

    var dismissPermanentlyButton: XCUIElement {
        buttons["Dismiss Permanently"]
    }

    var actionButton: XCUIElement {
        buttons["Action"]
    }

    var nextSteps: XCUIElement {
        webViews.firstMatch.staticTexts["Next Steps"]
    }
}
