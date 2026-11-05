//
//  ContentBlockingUITests.swift
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

final class ContentBlockingUITests: UITestCase {

    override var additionalLaunchArguments: [String] {
        // Initial defaults reset clears ToggleReportingStore's standard-defaults throttle.
        super.additionalLaunchArguments + ["-uiTestProtectionFeedback"]
    }

    private let trackerPageURL = "https://privacy-test-pages.site/tracker-reporting/1major-via-script.html"
    private let trackerPageTitle = "1 major tracker loaded via script src"

    func testPrivacyDashboardReportsBlockedTrackerAndPersistsDisabledProtection() {
        XCTContext.runActivity(named: "Inspect blocked tracker details") { _ in
            app.openURL(trackerPageURL, expecting: trackerPageTitle)
            app.openPrivacyDashboard(expectingProtectionState: true)
            app.assertPrivacyDashboard(isProtected: true, blockedTrackerVisible: true)

            app.privacyDashboard.descendants(matching: .any)["View Tracker Companies"].firstMatch.tapWhenHittable(in: app)
            XCTAssertTrue(
                app.privacyDashboard.staticTexts["doubleclick.net"].waitForExistence(timeout: UITestTimeouts.elementExistence),
                "Blocked tracker company did not appear.")
            app.privacyDashboard.descendants(matching: .any)["Back"].firstMatch.tapWhenHittable(in: app)
        }

        XCTContext.runActivity(named: "Disable protection from the Privacy Dashboard") { _ in
            app.privacyDashboard.switches["Disable Protections"].tapWhenHittable(in: app)
            app.dismissProtectionFeedback()
            app.assertPrivacyProtectionMenuState(isProtected: false)
            app.reloadCurrentPage(expecting: trackerPageTitle)

            app.openPrivacyDashboard(expectingProtectionState: false)
            app.assertPrivacyDashboard(isProtected: false, blockedTrackerVisible: false)
            app.closePrivacyDashboard()
        }
    }

    func testBrowsingMenuTogglesProtectionAndUndoRestoresPreviousState() {
        app.openURL(trackerPageURL, expecting: trackerPageTitle)
        app.waitForPrivacyInfo()

        XCTContext.runActivity(named: "Disable protection from the browsing menu") { _ in
            app.openBrowsingMenuItem("Browser.Menu.PrivacyProtection.Toggle")
            app.dismissProtectionFeedback()
            app.reloadCurrentPage(expecting: trackerPageTitle)

            app.openPrivacyDashboard(expectingProtectionState: false)
            app.assertPrivacyDashboard(isProtected: false, blockedTrackerVisible: false)
            app.closePrivacyDashboard()
        }

        XCTContext.runActivity(named: "Enable protection from the browsing menu") { _ in
            app.openBrowsingMenuItem("Browser.Menu.PrivacyProtection.Toggle")
            app.assertActionMessage(contains: "Privacy Protection enabled for privacy-test-pages.site", waitForDismissal: false)
            assertUndoIsAvailable()
            XCTAssertTrue(
                app.descendants(matching: .any)["Browser.ActionMessage"]
                    .wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.navigation),
                "Action message did not dismiss.")
            app.reloadCurrentPage(expecting: trackerPageTitle)

            app.openPrivacyDashboard(expectingProtectionState: true)
            app.assertPrivacyDashboard(isProtected: true, blockedTrackerVisible: true)
            app.closePrivacyDashboard()
        }

        XCTContext.runActivity(named: "Disable protection again") { _ in
            app.openBrowsingMenuItem("Browser.Menu.PrivacyProtection.Toggle")
            app.assertActionMessage(contains: "Privacy Protection disabled for privacy-test-pages.site", waitForDismissal: false)
            assertUndoIsAvailable()
            XCTAssertTrue(
                app.descendants(matching: .any)["Browser.ActionMessage"]
                    .wait(for: NSPredicate(format: "exists == false"), timeout: UITestTimeouts.navigation),
                "Action message did not dismiss.")
            app.reloadCurrentPage(expecting: trackerPageTitle)

            app.openPrivacyDashboard(expectingProtectionState: false)
            app.assertPrivacyDashboard(isProtected: false, blockedTrackerVisible: false)
            app.closePrivacyDashboard()
        }

        XCTContext.runActivity(named: "Undo enabling protection") { _ in
            app.openBrowsingMenuItem("Browser.Menu.PrivacyProtection.Toggle")
            app.assertActionMessage(
                contains: "Privacy Protection enabled for privacy-test-pages.site",
                waitForDismissal: false)
            app.buttons["Browser.ActionMessage.Action"].tapWhenHittable(in: app)
            app.assertActionMessage(contains: "Privacy Protection disabled for privacy-test-pages.site")
            app.assertPrivacyProtectionMenuState(isProtected: false)
            app.reloadCurrentPage(expecting: trackerPageTitle)

            app.openPrivacyDashboard(expectingProtectionState: false)
            app.assertPrivacyDashboard(isProtected: false, blockedTrackerVisible: false)
        }
    }
    private func assertUndoIsAvailable(file: StaticString = #filePath, line: UInt = #line) {
        let undo = app.descendants(matching: .any)["Browser.ActionMessage"].buttons["Browser.ActionMessage.Action"]
        XCTAssertTrue(undo.waitForExistence(timeout: UITestTimeouts.elementExistence), file: file, line: line)
        XCTAssertEqual(undo.label, "Undo", file: file, line: line)
    }

}
