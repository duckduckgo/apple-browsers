//
//  AIChatMigrationStoreTests.swift
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

import XCTest
@testable import AIChat

final class AIChatMigrationStoreTests: XCTestCase {

    func testStoreAppendsAndIncrementsCount() {
        let store = AIChatMigrationStore()
        XCTAssertEqual(store.info().count, 0)

        let ok1 = store.store("file-1")
        XCTAssertTrue(ok1.ok)
        XCTAssertEqual(store.info().count, 1)

        let ok2 = store.store(nil)
        XCTAssertTrue(ok2.ok)
        XCTAssertEqual(store.info().count, 2)

        // Verify payloads
        XCTAssertEqual(store.item(at: 0)?.serializedMigrationFile, "file-1")
        XCTAssertNil(store.item(at: 1)?.serializedMigrationFile)
    }

    func testItemAtHandlesNilNegativeAndOutOfBounds() {
        let store = AIChatMigrationStore()
        store.store("a")

        XCTAssertNil(store.item(at: nil))
        XCTAssertNil(store.item(at: -1))
        XCTAssertNil(store.item(at: 2))
        XCTAssertEqual(store.item(at: 0)?.serializedMigrationFile, "a")
    }

    func testInfoReturnsCorrectCount() {
        let store = AIChatMigrationStore()
        XCTAssertEqual(store.info().count, 0)
        store.store("x")
        XCTAssertEqual(store.info().count, 1)
        store.store("y")
        XCTAssertEqual(store.info().count, 2)
    }

    func testClearRemovesAllItems() {
        let store = AIChatMigrationStore()
        store.store("x")
        store.store("y")
        XCTAssertEqual(store.info().count, 2)

        let ok = store.clear()
        XCTAssertTrue(ok.ok)
        XCTAssertEqual(store.info().count, 0)
        XCTAssertNil(store.item(at: 0))
    }

    func testDTOsAreCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // AIChatMigrationData
        let migration = AIChatMigrationData(serializedMigrationFile: "abc")
        let migrationData = try encoder.encode(migration)
        let migrationDecoded = try decoder.decode(AIChatMigrationData.self, from: migrationData)
        XCTAssertEqual(migrationDecoded, migration)

        // AIChatOKResponse
        let ok = AIChatOKResponse()
        let okData = try encoder.encode(ok)
        let okDecoded = try decoder.decode(AIChatOKResponse.self, from: okData)
        XCTAssertEqual(okDecoded, ok)

        // AIChatCountResponse
        let count = AIChatCountResponse(count: 3)
        let countData = try encoder.encode(count)
        let countDecoded = try decoder.decode(AIChatCountResponse.self, from: countData)
        XCTAssertEqual(countDecoded, count)

        // AIChatErrorResponse
        let error = AIChatErrorResponse(reason: "invalid index")
        let errorData = try encoder.encode(error)
        let errorDecoded = try decoder.decode(AIChatErrorResponse.self, from: errorData)
        XCTAssertEqual(errorDecoded, error)
    }
}
