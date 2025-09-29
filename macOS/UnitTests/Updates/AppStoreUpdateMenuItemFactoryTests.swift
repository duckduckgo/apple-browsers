//
//  AppStoreUpdateMenuItemFactoryTests.swift
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
#if APPSTORE

import XCTest
import Cocoa
@testable import DuckDuckGo_Privacy_Browser

final class AppStoreUpdateMenuItemFactoryTests: XCTestCase {

    private var mockUpdate: Update!

    override func setUp() {
        super.setUp()
        autoreleasepool {
            mockUpdate = Update(
                isInstalled: false,
                type: .regular,
                version: "1.0.1",
                build: "101",
                date: Date(),
                releaseNotes: ["Bug fixes"],
                releaseNotesSubscription: [],
                needsLatestReleaseNote: false
            )
        }
    }

    override func tearDown() {
        mockUpdate = nil
        super.tearDown()
    }

    // MARK: - Menu Item Creation Tests

    func testMenuItem_SetsCorrectTitle() {
        // When
        let menuItem = AppStoreUpdateMenuItemFactory.menuItem(for: mockUpdate)

        // Then
        XCTAssertEqual(menuItem.title, UserText.updateAvailableMenuItemAppStore)
    }

    func testMenuItem_SetsCorrectTarget() {
        // When
        let menuItem = AppStoreUpdateMenuItemFactory.menuItem(for: mockUpdate)

        // Then
        XCTAssertTrue(menuItem.target === Application.appDelegate.updateController)
    }

    func testMenuItem_SetsCorrectAction() {
        // When
        let menuItem = AppStoreUpdateMenuItemFactory.menuItem(for: mockUpdate)

        // Then
        XCTAssertEqual(menuItem.action, #selector(AppStoreUpdateController.openUpdatesPage))
    }

    func testMenuItem_IsEnabled() {
        // When
        let menuItem = AppStoreUpdateMenuItemFactory.menuItem(for: mockUpdate)

        // Then
        XCTAssertTrue(menuItem.isEnabled)
    }

    // MARK: - Different Update Types

    func testMenuItem_WithCriticalUpdate() {
        // Given
        let criticalUpdate = Update(
            isInstalled: false,
            type: .critical,
            version: "1.0.1",
            build: "101",
            date: Date(),
            releaseNotes: ["Critical security fix"],
            releaseNotesSubscription: [],
            needsLatestReleaseNote: false
        )

        // When
        let menuItem = AppStoreUpdateMenuItemFactory.menuItem(for: criticalUpdate)

        // Then
        XCTAssertEqual(menuItem.title, UserText.updateAvailableMenuItemAppStore)
        XCTAssertEqual(menuItem.action, #selector(AppStoreUpdateController.openUpdatesPage))
    }

    func testMenuItem_WithInstalledUpdate() {
        // Given
        let installedUpdate = Update(
            isInstalled: true,
            type: .regular,
            version: "1.0.1",
            build: "101",
            date: Date(),
            releaseNotes: ["Bug fixes"],
            releaseNotesSubscription: [],
            needsLatestReleaseNote: false
        )

        // When
        let menuItem = AppStoreUpdateMenuItemFactory.menuItem(for: installedUpdate)

        // Then
        XCTAssertEqual(menuItem.title, UserText.updateAvailableMenuItemAppStore)
        XCTAssertEqual(menuItem.action, #selector(AppStoreUpdateController.openUpdatesPage))
    }
}

#endif
