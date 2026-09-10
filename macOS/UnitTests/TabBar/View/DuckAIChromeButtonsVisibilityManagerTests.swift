//
//  DuckAIChromeButtonsVisibilityManagerTests.swift
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

@testable import DuckDuckGo_Privacy_Browser

final class DuckAIChromeButtonsVisibilityManagerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeManager() -> LocalDuckAIChromeButtonsVisibilityManager {
        LocalDuckAIChromeButtonsVisibilityManager(
            persistor: DuckAIChromeButtonsUserDefaultsPersistor(keyValueStore: defaults)
        )
    }

    // MARK: - Menu-button layout migration

    func testWhenOnlyDuckAIButtonWasHiddenThenMigrationRestoresIt() {
        let manager = makeManager()
        manager.setHidden(true, for: .duckAI)

        manager.migrateVisibilityForMenuButtonLayoutIfNeeded()

        XCTAssertFalse(manager.isHidden(.duckAI))
    }

    func testWhenBothButtonsWereHiddenThenMigrationLeavesThemHidden() {
        let manager = makeManager()
        manager.setHidden(true, for: .duckAI)
        manager.setHidden(true, for: .sidebar)

        manager.migrateVisibilityForMenuButtonLayoutIfNeeded()

        XCTAssertTrue(manager.isHidden(.duckAI))
        XCTAssertTrue(manager.isHidden(.sidebar))
    }

    func testWhenNothingWasHiddenThenMigrationChangesNothing() {
        let manager = makeManager()

        manager.migrateVisibilityForMenuButtonLayoutIfNeeded()

        XCTAssertFalse(manager.isHidden(.duckAI))
        XCTAssertFalse(manager.isHidden(.sidebar))
    }

    func testWhenMigrationAlreadyRanThenLaterDeliberateHideIsPreserved() {
        let manager = makeManager()
        manager.setHidden(true, for: .duckAI)
        manager.migrateVisibilityForMenuButtonLayoutIfNeeded()
        XCTAssertFalse(manager.isHidden(.duckAI))

        // The user hides the pill on purpose, then the layout is applied again.
        manager.setHidden(true, for: .duckAI)
        manager.migrateVisibilityForMenuButtonLayoutIfNeeded()

        XCTAssertTrue(manager.isHidden(.duckAI))
    }

    func testWhenMigrationRunsRepeatedlyThenItIsIdempotent() {
        let manager = makeManager()
        manager.setHidden(true, for: .duckAI)

        for _ in 0..<3 {
            manager.migrateVisibilityForMenuButtonLayoutIfNeeded()
        }

        XCTAssertFalse(manager.isHidden(.duckAI))
    }

    func testWhenMigrationRunsThenItIsNotRepeatedOnAFreshManagerSharingStorage() {
        makeManager().migrateVisibilityForMenuButtonLayoutIfNeeded()

        // A second window builds its own manager over the same storage.
        let other = makeManager()
        other.setHidden(true, for: .duckAI)
        other.migrateVisibilityForMenuButtonLayoutIfNeeded()

        XCTAssertTrue(other.isHidden(.duckAI))
    }
}
