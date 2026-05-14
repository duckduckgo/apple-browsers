//
//  TabsModelPersistenceTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Persistence
@testable import DuckDuckGo
@testable import Core
@testable import PersistenceTestingUtils

class TabsModelPersistenceTests: XCTestCase {

    struct Constants {
        static let firstTitle = "a title"
        static let firstUrl = "http://example.com"
        static let secondTitle = "another title"
        static let secondUrl = "http://anotherurl.com"
    }

    var mockNormalStore: ThrowingKeyValueStoring!
    var mockFireStore: ThrowingKeyValueStoring!
    var mockLegacyStore: KeyValueStoring!
    var persistence: TabsModelPersisting!
    private var firstTab: Tab!
    private var secondTab: Tab!

    override func setUp() async throws {
        try await super.setUp()

        let normalStore = try MockKeyValueFileStore(throwOnInit: nil)
        let fireStore = try MockKeyValueFileStore(throwOnInit: nil)
        let legacyStore = MockKeyValueStore()
        mockNormalStore = normalStore
        mockFireStore = fireStore
        mockLegacyStore = legacyStore
        firstTab = tab(title: Constants.firstTitle, url: Constants.firstUrl)
        secondTab = tab(title: Constants.firstTitle, url: Constants.firstUrl)

        persistence = TabsModelPersistence(normalStore: normalStore,
                                           fireStore: fireStore,
                                           legacyStore: legacyStore)

        setupUserDefault(with: #file)
        UserDefaults.app.removeObject(forKey: "com.duckduckgo.opentabs")
    }

    private func tab(title: String, url: String) -> Tab {
        return Tab(link: Link(title: title, url: URL(string: url)!))
    }

    private var model: TabsModel {
        let model = TabsModel(tabs: [
            firstTab,
            secondTab
        ], desktop: UIDevice.current.userInterfaceIdiom == .pad)
        return model
    }

    // MARK: - Normal Key Tests

    func testBeforeModelSavedThenGetIsNil() throws {
        XCTAssertNil(try persistence.getTabsModel(for: .normal))
    }

    func testWhenModelSavedThenGetIsNotNil() throws {
        _ = persistence.save(model: model, for: .normal)
        XCTAssertNotNil(try persistence.getTabsModel(for: .normal))
    }

    func testWhenModelIsSavedThenGetLoadsCompleteTabs() throws {
        _ = persistence.save(model: model, for: .normal)

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.get(tabAt: 0), firstTab)
        XCTAssertEqual(loaded?.get(tabAt: 1), secondTab)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    func testWhenModelIsSavedThenGetLoadsModelWithCurrentSelection() throws {
        let model = self.model
        model.select(tab: model.tabs[1])
        _ = persistence.save(model: model, for: .normal)

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.currentIndex, 1)
    }

    func testWhenMigratingEmptyNoModelIsReturned() throws {
        XCTAssertNil(try persistence.getTabsModel(for: .normal))
    }

    func testWhenMigratingExistingItIsReturnedAndCleared() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    func testWhenNotMigratingThenOldValueIsIgnoredIfPresent() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let newData = try NSKeyedArchiver.archivedData(withRootObject: TabsModel(desktop: false), requiringSecureCoding: false)
        try mockNormalStore.set(newData, forKey: "TabsModelKey")

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    // MARK: - Fire Key Tests

    func testWhenFireModelNotSavedThenGetReturnsNil() throws {
        XCTAssertNil(try persistence.getTabsModel(for: .fire))
    }

    func testWhenFireModelSavedThenGetReturnsModel() throws {
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.save(model: fireModel, for: .fire)

        let loaded = try persistence.getTabsModel(for: .fire)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
    }

    func testWhenFireModelSavedThenGetLoadsWithFireMode() throws {
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.save(model: fireModel, for: .fire)

        let loaded = try persistence.getTabsModel(for: .fire)
        XCTAssertEqual(loaded?.mode, .fire)
    }

    func testWhenClearAllThenBothKeysCleared() throws {
        _ = persistence.save(model: model, for: .normal)
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.save(model: fireModel, for: .fire)

        persistence.clearAll()

        XCTAssertNil(try persistence.getTabsModel(for: .normal))
        XCTAssertNil(try persistence.getTabsModel(for: .fire))
    }

    func testWhenClearNormalThenFireModelUntouched() throws {
        _ = persistence.save(model: model, for: .normal)
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.save(model: fireModel, for: .fire)

        persistence.clear(for: .normal)

        XCTAssertNil(try persistence.getTabsModel(for: .normal))
        XCTAssertNotNil(try persistence.getTabsModel(for: .fire))
    }

    func testLegacyMigrationDoesNotRunForFireKey() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let loaded = try persistence.getTabsModel(for: .fire)
        XCTAssertNil(loaded)
    }

}
