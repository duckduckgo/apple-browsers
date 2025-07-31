//
//  NewTabPageProtectionsReportSettingsMigratorTests.swift
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

import NewTabPage
import Persistence
import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageProtectionsReportSettingsMigratorTests: XCTestCase {
    private var migrator: NewTabPageProtectionsReportSettingsMigrator!
    private var keyValueStore: MockKeyValueStore!

    typealias LegacyKey = NewTabPageProtectionsReportSettingsMigrator.LegacyKey

    override func setUp() {
        keyValueStore = MockKeyValueStore()
        migrator = NewTabPageProtectionsReportSettingsMigrator(legacyKeyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
    }

    // MARK: - isViewExpanded

    func testWhenRecentActivityIsNilAndPrivacyStatsIsNilThenViewIsExpanded() {
        XCTAssertTrue(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsCollapsedAndPrivacyStatsIsNilThenViewIsCollapsed() {
        keyValueStore.set(false, forKey: LegacyKey.newTabPageRecentActivityIsViewExpanded.rawValue)
        XCTAssertFalse(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsNilAndPrivacyStatsIsCollapsedThenViewIsCollapsed() {
        keyValueStore.set(false, forKey: LegacyKey.newTabPagePrivacyStatsIsViewExpanded.rawValue)
        XCTAssertFalse(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsCollapsedAndPrivacyStatsIsCollapsedThenViewIsCollapsed() {
        keyValueStore.set(false, forKey: LegacyKey.newTabPageRecentActivityIsViewExpanded.rawValue)
        keyValueStore.set(false, forKey: LegacyKey.newTabPagePrivacyStatsIsViewExpanded.rawValue)
        XCTAssertFalse(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsExpandedAndPrivacyStatsIsNilThenViewIsExpanded() {
        keyValueStore.set(true, forKey: LegacyKey.newTabPageRecentActivityIsViewExpanded.rawValue)
        XCTAssertTrue(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsNilAndPrivacyStatsIsExpandedThenViewIsExpanded() {
        keyValueStore.set(true, forKey: LegacyKey.newTabPagePrivacyStatsIsViewExpanded.rawValue)
        XCTAssertTrue(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsExpandedAndPrivacyStatsIsCollapsedThenViewIsExpanded() {
        keyValueStore.set(true, forKey: LegacyKey.newTabPageRecentActivityIsViewExpanded.rawValue)
        keyValueStore.set(false, forKey: LegacyKey.newTabPagePrivacyStatsIsViewExpanded.rawValue)
        XCTAssertTrue(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsCollapsedAndPrivacyStatsIsExpandedThenViewIsExpanded() {
        keyValueStore.set(false, forKey: LegacyKey.newTabPageRecentActivityIsViewExpanded.rawValue)
        keyValueStore.set(true, forKey: LegacyKey.newTabPagePrivacyStatsIsViewExpanded.rawValue)
        XCTAssertTrue(migrator.isViewExpanded)
    }

    func testWhenRecentActivityIsExpandedAndPrivacyStatsIsExpandedThenViewIsExpanded() {
        keyValueStore.set(true, forKey: LegacyKey.newTabPageRecentActivityIsViewExpanded.rawValue)
        keyValueStore.set(true, forKey: LegacyKey.newTabPagePrivacyStatsIsViewExpanded.rawValue)
        XCTAssertTrue(migrator.isViewExpanded)
    }

    // MARK: - activeFeed

    func testWhenIsNewUserIsNilThenActiveFeedIsPrivacyStats() {
        XCTAssertEqual(migrator.activeFeed, .privacyStats)
    }

    func testWhenIsNewUserIsFalseThenActiveFeedIsRecentActivity() {
        keyValueStore.set(false, forKey: LegacyKey.isNewUser.rawValue)
        XCTAssertEqual(migrator.activeFeed, .activity)
    }

    func testWhenIsNewUserIsTrueThenActiveFeedIsPrivacyStats() {
        keyValueStore.set(true, forKey: LegacyKey.isNewUser.rawValue)
        XCTAssertEqual(migrator.activeFeed, .privacyStats)
    }

    // MARK: - isProtectionsReportVisible

    func testWhenRecentActivityIsNilAndPrivacyStatsIsNilThenProtectionsReportIsVisible() {
        XCTAssertTrue(migrator.isProtectionsReportVisible)
    }

    func testWhenRecentActivityIsHiddenAndPrivacyStatsIsNilThenProtectionsReportIsHidden() {
        keyValueStore.set(false, forKey: LegacyKey.homePageIsRecentActivityVisible.rawValue)
        XCTAssertFalse(migrator.isProtectionsReportVisible)
    }

    func testWhenRecentActivityIsNilAndPrivacyStatsIsHiddenThenProtectionsReportIsHidden() {
        keyValueStore.set(false, forKey: LegacyKey.homePageIsPrivacyStatsVisible.rawValue)
        XCTAssertFalse(migrator.isProtectionsReportVisible)
    }

    func testWhenRecentActivityIsHiddenAndPrivacyStatsIsHiddenThenProtectionsReportIsHidden() {
        keyValueStore.set(false, forKey: LegacyKey.homePageIsRecentActivityVisible.rawValue)
        keyValueStore.set(false, forKey: LegacyKey.homePageIsPrivacyStatsVisible.rawValue)
        XCTAssertFalse(migrator.isProtectionsReportVisible)
    }

    func testWhenRecentActivityIsVisibleAndPrivacyStatsIsNilThenProtectionsReportIsVisible() {
        keyValueStore.set(true, forKey: LegacyKey.homePageIsRecentActivityVisible.rawValue)
        XCTAssertTrue(migrator.isProtectionsReportVisible)
    }

    func testWhenRecentActivityIsNilAndPrivacyStatsIsVisibleThenProtectionsReportIsVisible() {
        keyValueStore.set(true, forKey: LegacyKey.homePageIsPrivacyStatsVisible.rawValue)
        XCTAssertTrue(migrator.isProtectionsReportVisible)
    }

    func testWhenRecentActivityIsVisibleAndPrivacyStatsIsVisibleThenProtectionsReportIsVisible() {
        keyValueStore.set(true, forKey: LegacyKey.homePageIsRecentActivityVisible.rawValue)
        keyValueStore.set(true, forKey: LegacyKey.homePageIsPrivacyStatsVisible.rawValue)
        XCTAssertTrue(migrator.isProtectionsReportVisible)
    }
}
