//
//  ExpiryStorageTests.swift
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
@testable import PrivacyDashboard

final class ExpiryStorageTests: XCTestCase {

    func testAddAndRetrieveValue() throws {
        let expiryStorage = ExpiryStorage(keyValueStoring: MockKeyValueStore())
        expiryStorage.set(value: "value1", forKey: "key1", expiryDate: Date().addingTimeInterval(86400)) // +1 day

        let value = expiryStorage.value(forKey: "key1") as! String
        XCTAssertEqual(value, "value1")
    }

    func testExpiry() throws {
        let expiryStorage = ExpiryStorage(keyValueStoring: MockKeyValueStore())

        expiryStorage.set(value: "value1", forKey: "key1", expiryDate: Date().addingTimeInterval(-86400)) // -1 day
        XCTAssertEqual(expiryStorage.value(forKey: "key1") as! String, "value1")

        var removedCount = expiryStorage.removeExpiredItems(currentDate: Date())
        XCTAssertEqual(removedCount, 1)

        expiryStorage.set(value: "value1", forKey: "key1", expiryDate: Date().addingTimeInterval(-86400)) // -1 day
        expiryStorage.set(value: "value2", forKey: "key2", expiryDate: Date().addingTimeInterval(+86400)) // +1 day

        removedCount = expiryStorage.removeExpiredItems(currentDate: Date())
        XCTAssertEqual(removedCount, 1)

        XCTAssertNil(expiryStorage.value(forKey: "key1"))
        XCTAssertEqual(expiryStorage.value(forKey: "key2") as! String, "value2")
    }
}
