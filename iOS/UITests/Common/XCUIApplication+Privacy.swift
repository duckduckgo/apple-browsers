//
//  XCUIApplication+Privacy.swift
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

extension XCUIApplication {

    var privacyDashboard: XCUIElement {
        webViews["PrivacyDashboard.WebView"]
    }

    private var privacyIconButton: XCUIElement {
        buttons
            .matching(NSPredicate(
                format: "identifier == %@ OR identifier == %@",
                "PrivacyIcon",
                "privacy-icon-shield.button"))
            .firstMatch
    }

    private func privacyProtectionStatusField(isProtected: Bool) -> XCUIElement {
        let status = isProtected ? "Protections are ON for this site" : "Protections are OFF for this site"
        return privacyDashboard.textFields
            .matching(NSPredicate(format: "value == %@", status))
            .firstMatch
    }

    func waitForPrivacyInfo(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            privacyIconButton.waitForExistence(timeout: UITestTimeouts.navigation),
            "Privacy information did not become available for the loaded page.",
            file: file,
            line: line)
    }

    func assertPrivacyProtectionMenuState(
        isProtected: Bool,
        file: StaticString = #filePath,
        line: UInt = #line) {
        let toggle = openBrowsingMenu(revealing: "Browser.Menu.PrivacyProtection.Toggle", file: file, line: line)
        let menu = descendants(matching: .any)["Browser.Menu.List"]

        let expectedLabel = isProtected ? "Disable Privacy Protection" : "Enable Privacy Protection"
        XCTAssertTrue(
            toggle.wait(for: \.label, equals: expectedLabel, timeout: UITestTimeouts.elementExistence),
            "Browsing menu did not report the expected protection state.",
            file: file,
            line: line)

        buttons["Close"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            menu.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
            "Browsing menu did not close.",
            file: file,
            line: line)
    }

    func reloadCurrentPage(
        expecting pageText: String,
        file: StaticString = #filePath,
        line: UInt = #line) {
        let refreshButton = buttons["Browser.OmniBar.Button.Refresh"]
        refreshButton.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            refreshButton.wait(
                for: NSPredicate(format: "isHittable == true AND isEnabled == true"),
                timeout: UITestTimeouts.navigation),
            "Page reload did not finish.",
            file: file,
            line: line)
        assertPageContains(pageText, file: file, line: line)
    }

    func openPrivacyDashboard(
        expectingProtectionState isProtected: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line) {
        privacyIconButton.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            privacyDashboard.waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Privacy Dashboard did not appear.",
            file: file,
            line: line)

        guard let isProtected else { return }
        let expectedStatus = isProtected ? "ON" : "OFF"
        XCTAssertTrue(
            privacyProtectionStatusField(isProtected: isProtected)
                .waitForExistence(timeout: UITestTimeouts.navigation),
            "Privacy Dashboard did not reach the expected \(expectedStatus) state after the page reloaded.",
            file: file,
            line: line)
    }

    func closePrivacyDashboard(file: StaticString = #filePath, line: UInt = #line) {
        privacyDashboard.descendants(matching: .any)["Done"].firstMatch.tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            privacyDashboard.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.elementExistence),
            "Privacy Dashboard did not close.",
            file: file,
            line: line)
    }

    func assertPrivacyDashboard(
        isProtected: Bool,
        blockedTrackerVisible: Bool,
        file: StaticString = #filePath,
        line: UInt = #line) {
        let protectionStatus = isProtected ? "Protections are ON for this site" : "Protections are OFF for this site"
        XCTAssertTrue(
            privacyProtectionStatusField(isProtected: isProtected)
                .waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Expected Privacy Dashboard status '\(protectionStatus)'.",
            file: file,
            line: line)

        let blockedTracker = privacyDashboard.staticTexts["We blocked Google Ads (Google) from loading tracking requests on this page."]
        if blockedTrackerVisible {
            XCTAssertTrue(
                blockedTracker.waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Blocked tracker details did not appear.",
                file: file,
                line: line)
        } else {
            XCTAssertTrue(
                blockedTracker.wait(
                    for: NSPredicate(format: "exists == false"),
                    timeout: UITestTimeouts.elementExistence),
                "Blocked tracker details appeared while protection was disabled.",
                file: file,
                line: line)
        }
    }

    func dismissProtectionFeedback(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            privacyDashboard.staticTexts["Site not working? Let us know."].waitForExistence(timeout: UITestTimeouts.elementExistence),
            "Protection feedback prompt did not appear.",
            file: file,
            line: line)
        privacyDashboard.buttons["Don't Send"].tapWhenHittable(file: file, line: line)
        XCTAssertTrue(
            privacyDashboard.wait(
                for: NSPredicate(format: "exists == false"),
                timeout: UITestTimeouts.elementExistence),
            "Protection feedback did not close.",
            file: file,
            line: line)
        XCTAssertTrue(
            searchEntry.wait(for: NSPredicate(format: "isHittable == true"), timeout: UITestTimeouts.navigation),
            "Browser did not become interactive after dismissing protection feedback.",
            file: file,
            line: line)
    }

    func assertActionMessage(
        contains text: String,
        waitForDismissal: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line) {
        let message = staticTexts["Browser.ActionMessage.Message"]
        let actionMessage = descendants(matching: .any)["Browser.ActionMessage"]
        XCTAssertTrue(
            message.wait(for: \.label, contains: text, timeout: UITestTimeouts.elementExistence),
            "Expected action message containing '\(text)'.",
            file: file,
            line: line)
        if waitForDismissal {
            XCTAssertTrue(
                actionMessage.wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.navigation),
                "Action message did not dismiss.",
                file: file,
                line: line)
        }
    }
}
