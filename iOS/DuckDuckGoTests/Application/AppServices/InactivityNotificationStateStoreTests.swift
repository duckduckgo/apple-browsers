//
//  InactivityNotificationStateStoreTests.swift
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
@_spi(Testing) import Persistence
@testable import DuckDuckGo

final class InactivityNotificationStateStoreTests: XCTestCase {
    func testWhenNewStoreThenInteractionCountIsZero() throws {
        let store = InactivityNotificationStateStore(keyValueStore: MockKeyValueFileStore())
        XCTAssertEqual(store.interactionCount, 0)
    }

    func testWhenRecordInteractionThenCountIncrements() throws {
        let store = InactivityNotificationStateStore(keyValueStore: MockKeyValueFileStore())
        store.recordInteraction()
        store.recordInteraction()
        XCTAssertEqual(store.interactionCount, 2)
    }

    func testWhenPersistedCountThenNewStoreInstanceReadsIt() throws {
        let kv = MockKeyValueFileStore()
        let first = InactivityNotificationStateStore(keyValueStore: kv)
        first.recordInteraction()
        let second = InactivityNotificationStateStore(keyValueStore: kv)
        XCTAssertEqual(second.interactionCount, 1)
    }

    func testWhenReadFailsThenRecordInteractionDoesNotResetPersistedCount() throws {
        let kv = MockKeyValueFileStore(underlyingDict: [InactivityNotificationStateStore.StorageKey.interactionCount: 5])
        let store = InactivityNotificationStateStore(keyValueStore: kv)

        kv.throwOnRead = MockKeyValueFileStore.MockError.getError
        store.recordInteraction()

        // The write should have been abandoned rather than resetting the counter to 1.
        kv.throwOnRead = nil
        XCTAssertEqual(store.interactionCount, 5)
    }
}
