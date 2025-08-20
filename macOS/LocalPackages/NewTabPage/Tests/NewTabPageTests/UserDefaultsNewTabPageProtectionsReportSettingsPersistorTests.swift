//
//  UserDefaultsNewTabPageProtectionsReportSettingsPersistorTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PersistenceTestingUtils
@testable import NewTabPage

final class UserDefaultsNewTabPageProtectionsReportSettingsPersistorTests: XCTestCase {
    private var keyValueStore: MockKeyValueFileStore!
    private var persistor: UserDefaultsNewTabPageProtectionsReportSettingsPersistor!

    override func setUp() async throws {
        try await super.setUp()
        keyValueStore = try MockKeyValueFileStore()
        persistor = UserDefaultsNewTabPageProtectionsReportSettingsPersistor(
            keyValueStore,
            getLegacyIsViewExpanded: nil,
            getLegacyActiveFeed: nil
        )
    }

    // MARK: - Default Values Tests

    func testWhenNoValuesAreStoredThenDefaultValuesAreReturned() {
        XCTAssertTrue(persistor.isViewExpanded)
        XCTAssertEqual(persistor.activeFeed, .privacyStats)
    }

    // MARK: - View Expansion Tests

    func testWhenViewExpansionIsSetThenValueIsStored() throws {
        persistor.isViewExpanded = false
        XCTAssertEqual(try keyValueStore.object(forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.isViewExpanded) as? Bool, false)
    }

    func testWhenViewExpansionIsRetrievedThenStoredValueIsReturned() throws {
        try keyValueStore.set(true, forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.isViewExpanded)
        XCTAssertTrue(persistor.isViewExpanded)

        try keyValueStore.set(false, forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.isViewExpanded)
        XCTAssertFalse(persistor.isViewExpanded)
    }

    // MARK: - Active Feed Tests

    func testWhenActiveFeedIsSetThenValueIsStored() throws {
        persistor.activeFeed = .activity
        XCTAssertEqual(try keyValueStore.object(forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.activeFeed) as? String,
                       NewTabPageDataModel.Feed.activity.rawValue)
    }

    func testWhenActiveFeedIsRetrievedThenStoredValueIsReturned() throws {
        try keyValueStore.set(NewTabPageDataModel.Feed.activity.rawValue, forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.activeFeed)
        XCTAssertEqual(persistor.activeFeed, .activity)

        try keyValueStore.set(NewTabPageDataModel.Feed.privacyStats.rawValue, forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.activeFeed)
        XCTAssertEqual(persistor.activeFeed, .privacyStats)
    }

    func testWhenActiveFeedHasInvalidValueThenDefaultValueIsReturned() throws {
        try keyValueStore.set("invalid_feed", forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.activeFeed)
        XCTAssertEqual(persistor.activeFeed, .privacyStats)
    }

    // MARK: - Migration Tests

    func testWhenLegacyViewExpansionExistsThenValueIsMigrated() throws {
        let legacyValue = false
        keyValueStore = try MockKeyValueFileStore()
        persistor = UserDefaultsNewTabPageProtectionsReportSettingsPersistor(
            keyValueStore,
            getLegacyIsViewExpanded: legacyValue,
            getLegacyActiveFeed: nil
        )

        XCTAssertEqual(try keyValueStore.object(forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.isViewExpanded) as? Bool,
                       legacyValue)
    }

    func testWhenLegacyActiveFeedExistsThenValueIsMigrated() throws {
        let legacyValue = NewTabPageDataModel.Feed.activity
        keyValueStore = try MockKeyValueFileStore()
        persistor = UserDefaultsNewTabPageProtectionsReportSettingsPersistor(
            keyValueStore,
            getLegacyIsViewExpanded: nil,
            getLegacyActiveFeed: legacyValue
        )

        XCTAssertEqual(try keyValueStore.object(forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.activeFeed) as? String,
                       legacyValue.rawValue)
    }

    func testWhenNewValuesExistThenLegacyValuesAreNotMigrated() throws {
        keyValueStore = try MockKeyValueFileStore()
        try keyValueStore.set(true, forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.isViewExpanded)
        try keyValueStore.set(NewTabPageDataModel.Feed.privacyStats.rawValue, forKey: UserDefaultsNewTabPageProtectionsReportSettingsPersistor.Keys.activeFeed)

        persistor = UserDefaultsNewTabPageProtectionsReportSettingsPersistor(
            keyValueStore,
            getLegacyIsViewExpanded: false,
            getLegacyActiveFeed: .activity
        )

        XCTAssertTrue(persistor.isViewExpanded)
        XCTAssertEqual(persistor.activeFeed, .privacyStats)
    }
}
