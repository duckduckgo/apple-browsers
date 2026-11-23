//
//  UnprotectedSitesUITests.swift
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

final class UnprotectedSitesUITests: UITestCase {

    private let timeout = UITestTimeouts.navigation
    private let disableProtection = "Disable Privacy Protection"
    private let enableProtection = "Enable Privacy Protection"

    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_DISABLE_ANIMATIONS": "1"]
    }

    func testWhenProtectionIsDisabledForSiteThenItIsListedAndRemovingItRestoresProtection() throws {
        let site = try localWebsite()
        let host = String(site.hostAndPort.prefix { $0 != ":" })

        XCTContext.runActivity(named: "Disable protection from the browsing menu") { _ in
            site.open(.first, in: app)
            tapBrowsingMenuItem(disableProtection)
            dismissToggleReportIfShown()
        }

        XCTContext.runActivity(named: "The site is listed in Unprotected Sites") { _ in
            openUnprotectedSites()
            XCTAssertTrue(app.staticTexts[host].waitForExistence(timeout: timeout),
                          "\(host) is not listed in Unprotected Sites.")
        }

        XCTContext.runActivity(named: "Remove the site from the list") { _ in
            removeUnprotectedSite(host)
        }

        XCTContext.runActivity(named: "Protection is back on for the site") { _ in
            closeSettings()
            let item = revealBrowsingMenuItem(disableProtection)
            XCTAssertTrue(item.exists, "The browsing menu doesn't offer to disable protection again.")
            XCTAssertFalse(app.descendants(matching: .any)[enableProtection].exists)
        }
    }

    private func removeUnprotectedSite(_ domain: String, file: StaticString = #filePath, line: UInt = #line) {
        let site = app.staticTexts[domain]
        site.swipeLeft()
        app.buttons["Delete"].tapWhenHittable(in: app)
        XCTAssertTrue(site.waitForNonExistence(timeout: timeout), "\(domain) is still listed after removing it.",
                      file: file, line: line)
    }

    private func tapBrowsingMenuItem(_ label: String) {
        revealBrowsingMenuItem(label).tap()
    }

    @discardableResult
    private func revealBrowsingMenuItem(_ label: String) -> XCUIElement {
        app.dismissAddressBarEditing()
        app.buttons["Browser.Toolbar.Button.Menu"].tapWhenHittable(in: app)
        let menu = app.descendants(matching: .any)["Browser.Menu.List"]
        let item = app.buttons[label]
        menu.swipeUpToReveal(item, timeout: timeout)
        return item
    }

    private func dismissToggleReportIfShown() {
        let dontSend = app.buttons["Don't Send"]
        if dontSend.waitForExistence(timeout: UITestTimeouts.elementExistence) {
            dontSend.tap()
        }
    }

    private func openUnprotectedSites() {
        app.buttons["Browser.Toolbar.Button.Menu"].tapWhenHittable(in: app)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))

        tapScrollingIntoView(app.staticTexts["Web Tracking Protection"])
        XCTAssertTrue(app.navigationBars["Web Tracking Protection"].waitForExistence(timeout: timeout))

        tapScrollingIntoView(app.staticTexts["Unprotected Sites"])
        XCTAssertTrue(app.navigationBars["Unprotected Sites"].waitForExistence(timeout: timeout))
    }

    private func closeSettings() {
        app.navigationBars["Unprotected Sites"].buttons.firstMatch.tap()
        app.navigationBars["Web Tracking Protection"].buttons.firstMatch.tapWhenHittable(in: app)
        app.navigationBars["Settings"].buttons["Done"].tapWhenHittable(in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: timeout))
    }

    private func tapScrollingIntoView(_ element: XCUIElement) {
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        element.tap()
    }
}
