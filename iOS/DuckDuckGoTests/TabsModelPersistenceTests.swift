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

    var mockStore: ThrowingKeyValueStoring!
    var mockLegacyStore: KeyValueStoring!
    var persistence: TabsModelPersisting!

    override func setUp() async throws {
        try await super.setUp()

        let store = try MockKeyValueFileStore(throwOnInit: nil)
        let legacyStore = MockKeyValueStore()
        mockStore = store
        mockLegacyStore = legacyStore

        persistence = TabsModelPersistence(store: store,
                                           legacyStore: legacyStore)

        setupUserDefault(with: #file)
        UserDefaults.app.removeObject(forKey: "com.duckduckgo.opentabs")
    }

    private func tab(title: String, url: String) -> Tab {
        return Tab(link: Link(title: title, url: URL(string: url)!))
    }

    private var firstTab: Tab {
        return tab(title: Constants.firstTitle, url: Constants.firstUrl)
    }

    private var secondTab: Tab {
        return tab(title: Constants.firstTitle, url: Constants.firstUrl)
    }

    private var model: TabsModel {
        let model = TabsModel(tabs: [
            firstTab,
            secondTab
        ], desktop: UIDevice.current.userInterfaceIdiom == .pad)
        return model
    }

    func testBeforeModelSavedThenGetIsNil() throws {
        XCTAssertNil(try persistence.getTabsModel())
    }

    func testWhenModelSavedThenGetIsNotNil() throws {
        persistence.save(model: model)
        XCTAssertNotNil(try persistence.getTabsModel())
    }

    func testWhenModelIsSavedThenGetLoadsCompleteTabs() throws {
        persistence.save(model: model)

        let loaded = try persistence.getTabsModel()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.get(tabAt: 0), firstTab)
        XCTAssertEqual(loaded?.get(tabAt: 1), secondTab)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    func testWhenModelIsSavedThenGetLoadsModelWithCurrentSelection() throws {
        let model = self.model
        model.select(tabAt: 1)
        persistence.save(model: model)

        let loaded = try persistence.getTabsModel()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.currentIndex, 1)
    }

    func testWhenMigratingEmptyNoModelIsReturned() throws {
        XCTAssertNil(try persistence.getTabsModel())
    }

    func testWhenMigratingExistingItIsReturnedAndCleared() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let loaded = try persistence.getTabsModel()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    func testWhenNotMigratingThenOldValueIsIgnoredIfPresent() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let newData = try NSKeyedArchiver.archivedData(withRootObject: TabsModel(desktop: false), requiringSecureCoding: false)
        try mockStore.set(newData, forKey: "TabsModelKey")

        let loaded = try persistence.getTabsModel()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

}
