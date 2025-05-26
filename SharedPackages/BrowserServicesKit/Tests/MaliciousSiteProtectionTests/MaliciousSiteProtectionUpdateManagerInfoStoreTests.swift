//
//  MaliciousSiteProtectionUpdateManagerInfoStoreTests.swift
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

import Foundation
import XCTest

@testable import MaliciousSiteProtection

class MaliciousSiteProtectionUpdateManagerInfoStoreTests: XCTestCase {
    private var sut: UpdateManagerInfoStore!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDefaults = UserDefaults(suiteName: String(describing: Self.self))
        sut = UpdateManagerInfoStore(userDefaults: userDefaults)
        userDefaults.removePersistentDomain(forName: #file)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: String(describing: Self.self))
        userDefaults = nil
        sut = nil
        try super.tearDownWithError()
    }

    func testWhenLastHashPrefixesRefreshDateIsNotSetThenReturnDistantDate() {
        // GIVEN
        XCTAssertNil(userDefaults.object(forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastHashPrefixSetUpdateDate))

        // WHEN
        let result = sut.lastHashPrefixSetsUpdateDate

        // THEN
        XCTAssertEqual(result, .distantPast)
    }

    func testWhenLastHashPrefixesRefreshDateIsSetThenReturnThatDate() {
        // GIVEN
        let date = Date()
        userDefaults.set(date, forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastHashPrefixSetUpdateDate)

        // WHEN
        let result = sut.lastHashPrefixSetsUpdateDate

        // THEN
        XCTAssertEqual(result, date)
    }

    func testWhenSetLastHashPrefixesRefreshDateThenSaveIt() {
        // GIVEN
        let date = Date()
        XCTAssertNil(userDefaults.object(forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastHashPrefixSetUpdateDate))

        // WHEN
        sut.lastHashPrefixSetsUpdateDate = date

        // THEN
        XCTAssertEqual(
            userDefaults.object(forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastHashPrefixSetUpdateDate) as? Date,
            date
        )
    }

    func testWhenFilterSetsRefreshDateIsNotSetThenReturnDistantDate() {
        // GIVEN
        XCTAssertNil(userDefaults.object(forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastFilterSetUpdateDate))

        // WHEN
        let result = sut.lastHashPrefixSetsUpdateDate

        // THEN
        XCTAssertEqual(result, .distantPast)
    }

    func testWhenFilterSetsRefreshDateIsSetThenReturnThatDate() {
        // GIVEN
        let date = Date()
        userDefaults.set(date, forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastFilterSetUpdateDate)

        // WHEN
        let result = sut.lastFilterSetsUpdateDate

        // THEN
        XCTAssertEqual(result, date)
    }

    func testWhenSetFilterSetsRefreshDateThenSaveIt() {
        // GIVEN
        let date = Date()
        XCTAssertNil(userDefaults.object(forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastFilterSetUpdateDate))

        // WHEN
        sut.lastFilterSetsUpdateDate = date

        // THEN
        XCTAssertEqual(
            userDefaults.object(forKey: UpdateManagerInfoStore.Keys.maliciousSiteProtectionLastFilterSetUpdateDate) as? Date,
            date
        )
    }

}
