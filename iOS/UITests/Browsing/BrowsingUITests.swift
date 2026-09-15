//
//  BrowsingUITests.swift
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

final class BrowsingUITests: UITestCase {

    func testWhenURLIsEnteredThenPageLoads() {
        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
    }

    func testWhenPageLoadsThenRefreshBecomesAvailable() {
        XCTAssertTrue(
            app.searchEntry.waitForExistence(timeout: UITestTimeouts.navigation),
            "Browser UI did not appear after launch.")
        let refreshButton = app.buttons["Browser.OmniBar.Button.Refresh"]
        XCTAssertFalse(refreshButton.isHittable, "Refresh should not be available on the new tab page.")

        app.openURL("https://privacy-test-pages.site", expecting: "Privacy Test Pages")
        refreshButton.tapWhenHittable()

        app.assertPageContains("Privacy Test Pages")
    }
}
