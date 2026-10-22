//
//  CreditCardAutofillUITests.swift
//  DuckDuckGo
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
import UITestingSupport

final class CreditCardAutofillUITests: UITestCase {

    override var additionalLaunchArguments: [String] {
        super.additionalLaunchArguments + [
            "-config.rollout.autofill.autofillCreditCards", "true",
            "-config.rollout.autofill.autofillCreditCardsOnByDefault", "true"
        ]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        app.dismissAddressBarEditing()
        let menu = app.buttons["Browser.Toolbar.Button.Menu"]
        XCTAssertTrue(menu.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.navigation))
        menu.press(forDuration: 1)
        let debugList = app.descendants(matching: .any)["Debug.List"]
        XCTAssertTrue(debugList.waitForExistence(timeout: UITestTimeouts.navigation))
        let filter = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Filter")).firstMatch
        filter.tapWhenHittable()
        filter.typeText("Autofill")
        app.descendants(matching: .any)["Debug.Screen.Autofill"].tapWhenHittable()

        let table = app.tables.firstMatch
        let deleteCards = table.cells.containing(.staticText, identifier: "Delete All Credit Cards").firstMatch
        table.swipeUpToReveal(deleteCards, timeout: UITestTimeouts.navigation)
        deleteCards.tapWhenHittable()
        app.assertActionMessage(contains: "All credit cards deleted")
        let addCards = table.cells.containing(.staticText, identifier: "Add Test Credit Cards").firstMatch
        table.swipeUpToReveal(addCards, timeout: UITestTimeouts.navigation)
        addCards.tapWhenHittable()
        app.assertActionMessage(contains: "Credit Cards added")

        app.navigationBars["Autofill"].buttons["BackButton"].tapWhenHittable()
        XCTAssertTrue(debugList.waitForExistence(timeout: UITestTimeouts.elementExistence))
        if app.keyboards.firstMatch.exists {
            app.buttons.matching(NSPredicate(format: "label == %@", "close")).firstMatch.tapWhenHittable()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: UITestTimeouts.elementExistence))
        }
        app.buttons["Debug.Close"].tapWhenHittable()
        XCTAssertTrue(debugList.waitForNonExistence(timeout: UITestTimeouts.elementExistence))
    }

    func testSavedCardCanBeSelectedWithoutWebInputCoveringThePrompt() {
        app.openURL("https://privacy-test-pages.site/autofill/card-form-submission.html", expecting: "Card form with click handler")
        let cardNumber = app.webViews.textFields["Card Number"]
        cardNumber.tapWhenHittable()

        XCTAssertTrue(app.staticTexts["Use a saved card?"].waitForExistence(timeout: UITestTimeouts.navigation))
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: UITestTimeouts.elementExistence),
            "Web form keyboard remained above the credit-card prompt.")
        XCTAssertTrue(
            app.toolbars["Toolbar"].waitForNonExistence(timeout: UITestTimeouts.elementExistence),
            "Web form input accessory remained above the credit-card prompt.")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Credit-card prompt with web input dismissed"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "4444")).firstMatch.tapWhenHittable()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let authentication = springboard.staticTexts["Authenticate to fill credit card information"]
        XCTAssertTrue(authentication.waitForExistence(timeout: UITestTimeouts.navigation))
        springboard.enterSimulatorPasscode()
        XCTAssertTrue(authentication.waitForNonExistence(timeout: UITestTimeouts.navigation))
        XCTAssertTrue(
            cardNumber.wait(for: \.value, equals: "5555555555554444", timeout: UITestTimeouts.elementExistence),
            "Selecting the seeded card did not fill the web card-number field.")
    }
}
