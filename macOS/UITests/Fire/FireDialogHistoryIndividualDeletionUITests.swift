//
//  FireDialogHistoryIndividualDeletionUITests.swift
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

/// History View Individual Record Deletion Fire Dialog UI tests
final class FireDialogHistoryIndividualDeletionUITests: UITestCase, FireDialogUITests {

    override func setUp() {
        super.setUp()
        setUpFireDialogUITests()
    }

    func test_historyView_deleteSingleRecord_viaRightClick() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Right-click site 1 and select Delete from context menu
        site1Link.rightClick()
        try app.clickContextMenuItem { $0.title == "Delete" }

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

    func test_historyView_deleteSingleRecord_viaDeleteKey() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Click to select site 1
        site1Link.click()

        // Press Delete key
        app.typeKey(.delete, modifierFlags: [])

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

    func test_historyView_deleteSingleRecord_viaDeleteButton() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Click to select site 1
        site1Link.click()

        // Click Delete button in toolbar
        let deleteButton = historyWebView.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Delete button should appear when item is selected")
        deleteButton.click()

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

    func test_historyView_deleteSingleRecord_viaHoverGroupButton() throws {
        let site1Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.openSite(pageTitle: site1Title)

        let site2Title = UITests.randomPageTitle(length: lengthForRandomPageTitle)
        app.activateAddressBar()
        app.openSite(pageTitle: site2Title)

        // Open History view
        app.openHistory()
        let historyWebView = app.webViews["History"]
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should open")

        // Verify both sites exist
        let site1Link = historyWebView.links[site1Title]
        XCTAssertTrue(site1Link.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Site 1 should be in history")
        let site2Link = historyWebView.links[site2Title]
        XCTAssertTrue(site2Link.exists, "Site 2 should be in history")

        // Find the parent group containing site1Link
        let site1Group = historyWebView.groups.containing(.link, identifier: site1Title).firstMatch
        XCTAssertTrue(site1Group.exists, "Site 1 group should exist")

        // Hover the link to reveal the context menu button
        site1Link.hover()

        // Find the button that appears on hover and click using coordinates
        let groupButton = site1Group.buttons.firstMatch
        XCTAssertTrue(groupButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Group button should appear on hover")

        // Use button's x coordinate and link's y coordinate to click the correct button
        let buttonFrame = groupButton.frame
        let linkFrame = site1Link.frame
        let webViewFrame = historyWebView.frame

        // Calculate normalized coordinates relative to the web view
        let normalizedX = (buttonFrame.midX - webViewFrame.minX) / webViewFrame.width
        let normalizedY = (linkFrame.midY - webViewFrame.minY) / webViewFrame.height

        let coordinate = historyWebView.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: normalizedY))
        coordinate.click()

        // Click Delete from context menu
        try app.clickContextMenuItem { $0.title == "Delete" }

        // Verify Fire dialog does NOT appear (single record deletion is direct)
        XCTAssertFalse(fireDialogTitle.exists, "Fire dialog should not appear for single record deletion")

        // Verify site 1 deleted, site 2 preserved
        XCTAssertFalse(site1Link.exists, "Site 1 should be deleted")
        XCTAssertTrue(site2Link.exists, "Site 2 should still be in history")

        // Refresh history (Cmd+R)
        app.typeKey("r", modifierFlags: [.command])
        XCTAssertTrue(historyWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence), "History view should still exist after refresh")

        // Verify site 1 still deleted after refresh
        XCTAssertFalse(historyWebView.links[site1Title].exists, "Site 1 should not reappear after refresh")
        XCTAssertTrue(historyWebView.links[site2Title].exists, "Site 2 should still be in history after refresh")
    }

}
