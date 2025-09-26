//
//  FreeTrialBadgePersistorTests.swift
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
import Persistence
@testable import DuckDuckGo_Privacy_Browser

final class FreeTrialBadgePersistorTests: XCTestCase {

    private var mockKeyValueStore: MockKeyValueStore!
    private var persistor: FreeTrialBadgePersistor!

    override func setUp() {
        super.setUp()
        mockKeyValueStore = MockKeyValueStore()
        persistor = FreeTrialBadgePersistor(keyValueStore: mockKeyValueStore)
    }

    override func tearDown() {
        mockKeyValueStore = nil
        persistor = nil
        super.tearDown()
    }

    func testInitialViewCountIsZero() {
        XCTAssertEqual(persistor.viewCount, 0)
        XCTAssertFalse(persistor.hasReachedViewLimit)
    }

    func testIncrementViewCount() {
        persistor.incrementViewCount()
        XCTAssertEqual(persistor.viewCount, 1)
        XCTAssertFalse(persistor.hasReachedViewLimit)

        persistor.incrementViewCount()
        XCTAssertEqual(persistor.viewCount, 2)
        XCTAssertFalse(persistor.hasReachedViewLimit)

        persistor.incrementViewCount()
        XCTAssertEqual(persistor.viewCount, 3)
        XCTAssertFalse(persistor.hasReachedViewLimit)
    }

    func testViewLimitIsReachedAfterFourViews() {
        // Increment to 4 views
        for _ in 1...4 {
            persistor.incrementViewCount()
        }

        XCTAssertEqual(persistor.viewCount, 4)
        XCTAssertTrue(persistor.hasReachedViewLimit)
    }

    func testIncrementDoesNotExceedLimit() {
        // Increment to 4 views
        for _ in 1...4 {
            persistor.incrementViewCount()
        }

        // Try to increment beyond the limit
        persistor.incrementViewCount()
        persistor.incrementViewCount()

        // Should still be at the limit
        XCTAssertEqual(persistor.viewCount, 4)
        XCTAssertTrue(persistor.hasReachedViewLimit)
    }

    func testPersistenceAcrossInstances() {
        // Set a count with first instance
        persistor.incrementViewCount()
        persistor.incrementViewCount()

        // Create new instance with same store
        let newPersistor = FreeTrialBadgePersistor(keyValueStore: mockKeyValueStore)

        // Should have the same count
        XCTAssertEqual(newPersistor.viewCount, 2)
        XCTAssertFalse(newPersistor.hasReachedViewLimit)
    }
}

// Mock for testing
private final class MockKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey key: String) -> Any? {
        return storage[key]
    }

    func set(_ value: Any?, forKey key: String) {
        if let value = value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    func synchronize() -> Bool {
        return true
    }
}
