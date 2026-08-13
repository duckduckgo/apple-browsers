//
//  DuplicateTabTests.swift
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

// Regression test for: Duplicate Tab feature not working
// Asana: https://app.asana.com/1/137249556945/project/1199178362774117/task/1214147700081496
//
// The bug was introduced by PR #4227 (lazy load tabs). duplicateTab(at:) inserts an unloaded
// AnyTab and then immediately calls select(at:), which materialises the tab. Materialisation
// calls replaceTab(at:), which fires the tabCollectionViewModel(_:didReplaceTabAt:) delegate
// callback BEFORE tabCollectionViewModelDidInsert has been called. The NSCollectionView
// receives reloadItems(at:IndexPath(item:1)) while it still has only one item, leaving it in
// an inconsistent state so the subsequent insertItems call silently fails.
class DuplicateTabTests: UITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.openNewWindow()
    }

    func test_duplicateTab_appearsInTabBar_viaWindowMenu() throws {
        app.openSite(pageTitle: "DuplicateTabTest")

        let tabs = app.tabGroups.matching(identifier: "Tabs").radioButtons
        XCTAssertTrue(
            tabs.element(boundBy: 0).waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Initial tab should be visible in the tab bar"
        )
        let initialCount = tabs.count
        XCTAssertGreaterThanOrEqual(initialCount, 1, "Should have at least 1 tab before duplicating")

        app.menuItems["Duplicate Tab"].tap()

        // Bug: the duplicate tab is created in the model but never appears in the tab bar
        XCTAssertTrue(
            tabs.wait(for: \.count, equals: initialCount + 1, timeout: UITests.Timeouts.elementExistence),
            "Tab bar should show \(initialCount + 1) tabs after duplicating, found \(tabs.count)"
        )
    }

}
