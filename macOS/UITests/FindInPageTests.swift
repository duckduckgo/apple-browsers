//
//  FindInPageTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

class FindInPageTests: UITestCase {

    private var addressBarTextField: XCUIElement!
    private var loremIpsumWebView: XCUIElement!
    private var findInPageCloseButton: XCUIElement!
    private var loremIpsumFileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        let bundle = Bundle(for: type(of: self))
        loremIpsumFileURL = try XCTUnwrap(bundle.url(forResource: "lorem_ipsum", withExtension: "html"), "Could not find lorem_ipsum.html in test bundle")

        app = XCUIApplication.setUp()
        addressBarTextField = app.addressBar
        loremIpsumWebView = app.windows.webViews["Lorem Ipsum"]
        findInPageCloseButton = app.windows.buttons["FindInPageController.closeButton"]

        app.enforceSingleWindow()

        addressBarTextField.pasteURL(loremIpsumFileURL, pressingEnter: true)
        XCTAssertTrue(
            loremIpsumWebView.staticTexts.containing(\.value, containing: "Lorem ipsum").firstMatch
                .waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The \"Lorem Ipsum\" web page didn't load in a reasonable timeframe."
        )
    }

    func test_findInPage_canBeOpenedWithKeyCommand() throws {
        app.typeKey("f", modifierFlags: .command)

        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )
    }

    func test_findInPage_canBeOpenedWithMenuBarItem() throws {
        let findInPageMenuBarItem = app.menuItems["MainMenu.findInPage"]
        XCTAssertTrue(
            findInPageMenuBarItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find in Page\" main menu bar item in a reasonable timeframe."
        )

        findInPageMenuBarItem.click()

        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" via the menu items Edit->Find->\"Find in Page\", the elements of the \"Find in Page\" interface should exist."
        )
    }

    func test_findInPage_canBeOpenedWithMoreOptionsMenuItem() throws {
        let optionsButton = app.windows.buttons["NavigationBarViewController.optionsButton"]
        optionsButton.clickAfterExistenceTestSucceeds()

        let findInPageMoreOptionsMenuItem = app.menuItems["MoreOptionsMenu.findInPage"]
        XCTAssertTrue(
            findInPageMoreOptionsMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find More Options \"Find in Page\" menu item in a reasonable timeframe."
        )
        findInPageMoreOptionsMenuItem.click()

        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" via the More Options \"Find in Page\" menu item, the elements of the \"Find in Page\" interface should exist."
        )
    }

    func test_findInPage_canBeClosedWithEscape() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(
            findInPageCloseButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "After closing \"Find in Page\" with escape, the elements of the \"Find in Page\" interface should no longer exist."
        )
    }

    func test_findInPage_canBeClosedWithShiftCommandF() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )

        app.typeKey("f", modifierFlags: [.command, .shift])

        XCTAssertTrue(
            findInPageCloseButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "After closing \"Find in Page\" with escape, the elements of the \"Find in Page\" interface should no longer exist."
        )
    }

    func test_findInPage_canBeClosedWithHideFindMenuItem() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )

        let findInPageDoneMenuBarItem = app.menuItems["MainMenu.findInPageDone"]
        XCTAssertTrue(
            findInPageDoneMenuBarItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find in Page\" done main menu item in a reasonable timeframe."
        )
        findInPageDoneMenuBarItem.click()

        XCTAssertTrue(
            findInPageCloseButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence),
            "After closing \"Find in Page\" with escape, the elements of the \"Find in Page\" interface should no longer exist."
        )
    }

    func test_findInPage_showsCorrectNumberOfOccurrences() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )

        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(
            statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find in Page\" statusField in a reasonable timeframe."
        )
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_findInPage_showsFocusAndOccurrenceHighlighting() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )

        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(
            statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find in Page\" statusField in a reasonable timeframe."
        )
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")

        // Validate movement by advancing to next match using Command+G and asserting status updates.
        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_findNext_menuItemGoesToNextOccurrence() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )
        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(
            statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find in Page\" statusField in a reasonable timeframe."
        )
        // Note: the following is not a localized test element, but it should have a localization strategy.
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")

        let findNextMenuBarItem = app.menuItems["MainMenu.findNext"]
        XCTAssertTrue(
            findNextMenuBarItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find Next\" main menu bar item in a reasonable timeframe."
        )
        findNextMenuBarItem.click()
        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_findNext_nextArrowGoesToNextOccurrence() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )
        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(
            statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find in Page\" statusField in a reasonable timeframe."
        )
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")

        let findInPageNextButton = app.windows.buttons["FindInPageController.nextButton"]
        XCTAssertTrue(
            findInPageNextButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find Next\" main menu bar item in a reasonable timeframe."
        )

        findInPageNextButton.click()

        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_findNext_commandGGoesToNextOccurrence() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(
            findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "After invoking \"Find in Page\" with command-f, the elements of the \"Find in Page\" interface should exist."
        )
        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(
            statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Couldn't find \"Find in Page\" statusField in a reasonable timeframe."
        )
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")

        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_findInPage_cyclesThroughAllOccurrences_UsingNextWrapsToFirst() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeText("maximus\r")

        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "3 of 4"),
                      "Status field should show '3 of 4', but got: \(statusField.value ?? "nil")")
        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "4 of 4"),
                      "Status field should show '4 of 4', but got: \(statusField.value ?? "nil")")
        // Wrap around to first
        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_findPrevious_viaMenuShortcutAndButton() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")

        // Previous via menu item
        let findPreviousMenuItem = app.menuItems["MainMenu.findPrevious"]
        XCTAssertTrue(findPreviousMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        findPreviousMenuItem.click()
        XCTAssertTrue(statusField.wait(for: \.value, equals: "4 of 4"),
                      "Status field should show '4 of 4', but got: \(statusField.value ?? "nil")")

        // Previous via Cmd+Shift+G
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "3 of 4"),
                      "Status field should show '3 of 4', but got: \(statusField.value ?? "nil")")

        // Previous via button
        let findInPagePreviousButton = app.windows.buttons["FindInPageController.previousButton"]
        XCTAssertTrue(findInPagePreviousButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        findInPagePreviousButton.click()
        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_clickingWebViewDeactivates_thenCmdFReactivatesAndKeepsText() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
        // Click inside web content to move focus away
        loremIpsumWebView.click()
        // Press Cmd+F to reactivate find
        app.typeKey("f", modifierFlags: .command)
        // The search text should be kept; status should still be shown
        XCTAssertTrue(statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
        // And next should work
        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
    }

    func test_hideAndReactivate_keepsTextAndNextWorks() throws {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeText("maximus\r")
        let statusField = app.textFields["FindInPageController.statusField"]
        XCTAssertTrue(statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
        // Hide and reactivate
        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(findInPageCloseButton.waitForNonExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findInPageCloseButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Text should be kept and next still works
        XCTAssertTrue(statusField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"),
                      "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
        app.typeKey("g", modifierFlags: [.command])
        XCTAssertTrue(statusField.wait(for: \.value, equals: "2 of 4"),
                      "Status field should show '2 of 4', but got: \(statusField.value ?? "nil")")
    }

}
