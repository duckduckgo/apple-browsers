//
//  FireproofingSettingsViewControllerTests.swift
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

import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class FireproofingSettingsViewControllerTests: XCTestCase {

    func testEmptyListShowsPlaceholderAndHidesEditButton() {
        let controller = makeController(fireproofing: MockFireproofing())
        let table = controller.tableView!
        let section = FireproofingSettingsViewController.Section.domainList.rawValue

        XCTAssertEqual(controller.title, UserText.fireproofingListTitle)
        XCTAssertEqual(table.style, .insetGrouped)
        XCTAssertEqual(controller.tableView(table, numberOfRowsInSection: section), 1)
        XCTAssertEqual(controller.tableView(table, cellForRowAt: IndexPath(row: 0, section: section)).textLabel?.text,
                       UserText.fireproofingEmptyState)
        XCTAssertTrue(controller.navigationItem.rightBarButtonItems?.isEmpty ?? true)
        XCTAssertFalse(controller.tableView(table, canEditRowAt: IndexPath(row: 0, section: section)))
    }

    func testSwitchLoadsSavedValueAndUpdatesLoginDetection() throws {
        let fireproofing = MockFireproofing()
        fireproofing.loginDetectionEnabled = true
        let controller = makeController(fireproofing: fireproofing)
        let indexPath = IndexPath(row: 0, section: FireproofingSettingsViewController.Section.toggle.rawValue)
        let cell = try XCTUnwrap(controller.tableView(controller.tableView, cellForRowAt: indexPath) as? FireproofingSwitchCell)

        XCTAssertTrue(cell.toggle.isOn)
        XCTAssertEqual(cell.label.text, UserText.fireproofingAskOnSignIn)
        cell.toggle.isOn = false
        cell.toggle.sendActions(for: .valueChanged)
        XCTAssertFalse(fireproofing.loginDetectionEnabled)
        cell.toggle.isOn = true
        cell.toggle.sendActions(for: .valueChanged)
        XCTAssertTrue(fireproofing.loginDetectionEnabled)
    }

    func testEditAndDoneButtonsToggleEditingAndRemoveAllSection() throws {
        let controller = makeController(fireproofing: MockFireproofing(domains: ["www.zebra.com", "apple.com"]))
        let table = controller.tableView!
        let domainSection = FireproofingSettingsViewController.Section.domainList.rawValue
        let domainCell = try XCTUnwrap(controller.tableView(table, cellForRowAt: IndexPath(row: 0, section: domainSection))
            as? FireproofingDomainCell)
        XCTAssertEqual(domainCell.label.text, "apple.com")
        XCTAssertEqual(controller.numberOfSections(in: table), 3)
        XCTAssertTrue(table.allowsSelectionDuringEditing)

        let edit = try XCTUnwrap(controller.navigationItem.rightBarButtonItem)
        XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(edit.action), to: edit.target, from: edit, for: nil))
        XCTAssertTrue(table.isEditing)
        XCTAssertEqual(controller.numberOfSections(in: table), 4)
        let clearAll = controller.tableView(table, cellForRowAt: IndexPath(row: 0, section: 3))
        XCTAssertEqual(clearAll.textLabel?.text, UserText.fireproofingRemoveAllSites)
        XCTAssertTrue(clearAll.accessibilityTraits.contains(.button))

        let done = try XCTUnwrap(controller.navigationItem.rightBarButtonItem)
        XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(done.action), to: done.target, from: done, for: nil))
        XCTAssertFalse(table.isEditing)
        XCTAssertEqual(controller.numberOfSections(in: table), 3)
        XCTAssertFalse(controller.navigationItem.hidesBackButton)
        XCTAssertTrue(controller.navigationItem.rightBarButtonItem === edit)
    }

    private func makeController(fireproofing: MockFireproofing) -> FireproofingSettingsViewController {
        let controller = FireproofingSettingsViewController(fireproofing: fireproofing,
                                                            favicons: Favicons(fireproofing: fireproofing),
                                                            websiteDataManager: MockWebsiteDataManager())
        controller.loadViewIfNeeded()
        return controller
    }
}
