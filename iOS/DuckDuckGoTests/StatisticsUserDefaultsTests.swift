//
//  StatisticsUserDefaultsTests.swift
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

import BrowserServicesKit
import Foundation
import XCTest
@testable import Core

final class StatisticsUserDefaultsTests: XCTestCase {

    private static let suiteName = "StatisticsUserDefaultsCoreCompatibilityTestSuite"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    func testWhenUsingCoreAliasAsStatisticsStoreThenProtocolBehaviorIsAvailable() {
        let concreteStore = StatisticsUserDefaults(groupName: Self.suiteName)
        let store: BrowserServicesKit.StatisticsStore = concreteStore

        store.atb = "v123-4"
        store.variant = "ru"

        XCTAssertEqual(store.atbWithVariant, "v123-4ru")
    }

}
