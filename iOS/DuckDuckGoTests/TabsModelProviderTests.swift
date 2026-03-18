//
//  TabsModelProviderTests.swift
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

@testable import DuckDuckGo
import Core

final class TabsModelProviderTests: XCTestCase {

    private let exampleLink = Link(title: nil, url: URL(string: "https://example.com")!)

    // MARK: - Aggregate Count
    
    func testWhenNormalModelHasDefaultTabAndFireModelIsEmptyThenAggregateCountIsOne() throws {
        let normalModel = TabsModel(desktop: false)
        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)

        let sut = makeSUT(normalModel: normalModel, fireModel: fireModel)

        XCTAssertEqual(sut.aggregateTabsModel.count, 1)
    }

    func testWhenBothModelsHaveTabsThenAggregateCountIsSumOfBoth() {
        let normalModel = TabsModel(tabs: [
            Tab(link: exampleLink),
            Tab(link: exampleLink)
        ], desktop: false)
        let fireModel = TabsModel(tabs: [
            Tab(link: exampleLink, fireTab: true),
            Tab(link: exampleLink, fireTab: true),
            Tab(link: exampleLink, fireTab: true)
        ], desktop: false, mode: .fire)

        let sut = makeSUT(normalModel: normalModel, fireModel: fireModel)

        XCTAssertEqual(sut.aggregateTabsModel.count, 5)
    }

    // MARK: - Aggregate Count Updates Dynamically

    func testWhenTabAddedThenAggregateCountUpdates() {
        let normalModel = TabsModel(desktop: false)
        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)

        let sut = makeSUT(normalModel: normalModel, fireModel: fireModel)
        let initialCount = sut.aggregateTabsModel.count

        normalModel.insert(tab: Tab(link: exampleLink), placement: .atEnd, selectNewTab: true)

        XCTAssertEqual(sut.aggregateTabsModel.count, initialCount + 1)
    }

    func testWhenTabRemovedThenAggregateCountUpdates() {
        let fireModel = TabsModel(tabs: [
            Tab(link: exampleLink, fireTab: true),
            Tab(link: exampleLink, fireTab: true)
        ], desktop: false, mode: .fire)
        let normalModel = TabsModel(desktop: false)

        let sut = makeSUT(normalModel: normalModel, fireModel: fireModel)

        let tabToRemove = fireModel.tabs[0]
        fireModel.remove(tab: tabToRemove)

        XCTAssertEqual(sut.aggregateTabsModel.count, normalModel.count + fireModel.count)
    }

    // MARK: - Save

    func testWhenSaveCalledThenPersistenceReceivesBothModels() {
        let normalModel = TabsModel(desktop: false)
        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)
        let persistence = MockTabsModelPersistence()

        let sut = makeSUT(normalModel: normalModel, fireModel: fireModel, persistence: persistence)

        _ = sut.save()

        XCTAssertEqual(persistence.savedModels.count, 2)
        XCTAssertTrue(persistence.savedModels.contains { $0.key == .normal && $0.model === normalModel })
        XCTAssertTrue(persistence.savedModels.contains { $0.key == .fire && $0.model === fireModel })
    }

    // MARK: - Helpers

    private func makeSUT(normalModel: TabsModel = TabsModel(desktop: false),
                         fireModel: TabsModel = TabsModel(tabs: [], desktop: false, mode: .fire),
                         persistence: TabsModelPersisting = MockTabsModelPersistence()) -> TabsModelProvider {
        TabsModelProvider(normalTabsModel: normalModel, fireModeTabsModel: fireModel, persistence: persistence)
    }
}

// MARK: - Mocks

private final class MockTabsModelPersistence: TabsModelPersisting {

    struct SavedModel {
        let model: TabsModel
        let key: TabsModelStorageKey
    }

    private(set) var savedModels: [SavedModel] = []

    func getTabsModel(for key: TabsModelStorageKey) throws -> TabsModel? {
        nil
    }

    func save(model: TabsModel, for key: TabsModelStorageKey) -> Result<Void, Error> {
        savedModels.append(SavedModel(model: model, key: key))
        return .success(())
    }

    func clear(for key: TabsModelStorageKey) {}

    func clearAll() {}
}
