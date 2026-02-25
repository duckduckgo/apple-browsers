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

    func testWhenNormalModelHasDefaultTabAndFireModelIsEmptyThenAggregateCountIsOne() {
        let normalModel = TabsModel(desktop: false)
        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)

        let sut = TabsModelProvider(normalTabsModel: normalModel, fireModeTabsModel: fireModel)

        XCTAssertEqual(sut.aggregateTabsModel.count, 1)
    }

    func testWhenBothModelsHaveTabsThenAggregateCountIsSumOfBoth() {
        let normalModel = TabsModel(tabs: [
            Tab(link: exampleLink),
            Tab(link: exampleLink)
        ], desktop: false)
        let fireModel = TabsModel(tabs: [
            Tab(link: exampleLink),
            Tab(link: exampleLink),
            Tab(link: exampleLink)
        ], desktop: false, mode: .fire)

        let sut = TabsModelProvider(normalTabsModel: normalModel, fireModeTabsModel: fireModel)

        XCTAssertEqual(sut.aggregateTabsModel.count, 5)
    }

    // MARK: - Aggregate Count Updates Dynamically

    func testWhenTabAddedThenAggregateCountUpdates() {
        let normalModel = TabsModel(desktop: false)
        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)

        let sut = TabsModelProvider(normalTabsModel: normalModel, fireModeTabsModel: fireModel)
        let initialCount = sut.aggregateTabsModel.count

        normalModel.add(tab: Tab(link: exampleLink))

        XCTAssertEqual(sut.aggregateTabsModel.count, initialCount + 1)
    }

    func testWhenTabRemovedThenAggregateCountUpdates() {
        let fireModel = TabsModel(tabs: [
            Tab(link: exampleLink),
            Tab(link: exampleLink)
        ], desktop: false, mode: .fire)
        let normalModel = TabsModel(desktop: false)

        let sut = TabsModelProvider(normalTabsModel: normalModel, fireModeTabsModel: fireModel)

        fireModel.remove(at: 0)

        XCTAssertEqual(sut.aggregateTabsModel.count, normalModel.count + fireModel.count)
    }
}
