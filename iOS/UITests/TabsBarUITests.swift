//
//  TabsBarUITests.swift
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

import Swifter
import UIKit
import XCTest
import UITestingSupport

final class TabsBarUITests: XCTestCase {

    private let app = XCUIApplication()
    private let server = HttpServer()
    private var baseURL = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the iPad tab bar.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        server["/source"] = { _ in
            .ok(.html("""
            <!doctype html>
            <html lang="en">
              <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Source page</title></head>
              <body><h1>Source page</h1><a href="/background">Open destination</a></body>
            </html>
            """))
        }
        server["/background"] = { _ in
            .ok(.html("""
            <!doctype html>
            <html lang="en">
              <head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Background destination</title></head>
              <body><h1>Background destination</h1></body>
            </html>
            """))
        }
        try server.start(0, forceIPv4: true, priority: .userInitiated)
        baseURL = "http://127.0.0.1:\(try server.port())"
        app.launchArguments = [
            "-clearAllDefaults", "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        server.stop()
        XCUIDevice.shared.orientation = .portrait
        try super.tearDownWithError()
    }

    func testOpenInBackgroundRevealsNewTabWithoutSwitchingPagesWhenTabBarOverflows() throws {
        try assertBackgroundTabIsRevealed(additionalTabs: 12)
    }

    func testOpenInBackgroundRevealsNewTabWithoutSwitchingPagesWhenTabsFit() throws {
        try assertBackgroundTabIsRevealed(additionalTabs: 1)
    }

    private func assertBackgroundTabIsRevealed(additionalTabs: Int) throws {
        let addTab = app.buttons["Add 24"]
        let tabCount = app.buttons["Browser.Toolbar.Button.TabSwitcher"].staticTexts.firstMatch
        XCTAssertTrue(addTab.waitForExistence(timeout: UITestTimeouts.elementExistence))
        let initialCount = try XCTUnwrap(Int(tabCount.label))
        for index in 1...additionalTabs {
            addTab.tap()
            XCTAssertTrue(tabCount.wait(for: \.label, equals: String(initialCount + index)))
        }

        let searchEntry = app.descendants(matching: .any)["searchEntry"]
        searchEntry.tap()
        searchEntry.typeText("\(baseURL)/source\r")
        let sourceHeading = app.webViews.staticTexts["Source page"]
        XCTAssertTrue(sourceHeading.waitForExistence(timeout: UITestTimeouts.localTestServer))

        let link = app.webViews.links["Open destination"]
        XCTAssertTrue(link.waitForExistence(timeout: UITestTimeouts.elementExistence))
        link.press(forDuration: 1)
        let openInBackground = app.buttons["Open in Background"]
        XCTAssertTrue(openInBackground.waitForExistence(timeout: UITestTimeouts.elementExistence))
        openInBackground.tap()

        XCTAssertTrue(tabCount.wait(for: \.label, equals: String(initialCount + additionalTabs + 1)))
        let backgroundTab = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR label == %@",
            "Open \"127.0.0.1\" at 127.0.0.1",
            "Open \"Background destination\" at 127.0.0.1"
        )).firstMatch
        XCTAssertTrue(backgroundTab.waitForExistence(timeout: UITestTimeouts.localTestServer))
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            backgroundTab.exists && backgroundTab.isHittable
                && backgroundTab.frame.minX >= self.app.frame.minX
                && backgroundTab.frame.maxX <= addTab.frame.minX
        }, object: nil)
        let revealResult = XCTWaiter.wait(for: [revealed], timeout: UITestTimeouts.elementExistence)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(revealResult, .completed,
                       "The background tab should appear without manually scrolling the tab bar.")
        XCTAssertTrue(sourceHeading.isHittable, "Opening in the background should keep the source page active.")
        XCTAssertFalse(app.webViews.staticTexts["Background destination"].exists)

        backgroundTab.tap()
        XCTAssertTrue(app.webViews.staticTexts["Background destination"].waitForExistence(timeout: UITestTimeouts.localTestServer))
    }
}
