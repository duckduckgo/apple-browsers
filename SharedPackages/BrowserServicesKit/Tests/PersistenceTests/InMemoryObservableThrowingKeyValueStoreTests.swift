//
//  InMemoryObservableThrowingKeyValueStoreTests.swift
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

import Combine
import Foundation
import Persistence
import PersistenceTestingUtils
import Testing

final class InMemoryObservableThrowingKeyValueStoreTests {

    private var cancellables: Set<AnyCancellable>

    init() {
        cancellables = []
    }

    @Test("Get and set observable throwing value")
    func getAndSet() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"

        // Given - empty store
        #expect(try store.object(forKey: key) as? Int == nil)

        // When - set a value
        try store.set(42, forKey: key)

        // Then - value is retrieved
        #expect(try store.object(forKey: key) as? Int == 42)
    }

    @Test("Throws on get")
    func throwsOnGet() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"
        store.shouldThrowOnGet = true

        // When/Then - get throws
        #expect(throws: InMemoryObservableThrowingKeyValueStore.MockError.getError) {
            try store.object(forKey: key)
        }
    }

    @Test("Throws on set")
    func throwsOnSet() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"
        store.shouldThrowOnSet = true

        // When/Then - set throws
        #expect(throws: InMemoryObservableThrowingKeyValueStore.MockError.setError) {
            try store.set(42, forKey: key)
        }
    }

    @Test("Remove value sets to nil")
    func removeValue() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"

        // Given - value exists
        try store.set(42, forKey: key)
        #expect(try store.object(forKey: key) as? Int == 42)

        // When - remove
        try store.removeObject(forKey: key)

        // Then - value is removed
        #expect(try store.object(forKey: key) as? Int == nil)
    }

    @Test("Multiple properties store independently")
    func multipleProperties() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key1 = "observableThrowingValue"
        let key2 = "observableThrowingName"

        // When - set values for different keys
        try store.set(42, forKey: key1)
        try store.set("Alice", forKey: key2)

        // Then - both values are stored independently
        #expect(try store.object(forKey: key1) as? Int == 42)
        #expect(try store.object(forKey: key2) as? String == "Alice")

        // When - modify one
        try store.set(100, forKey: key1)

        // Then - other remains unchanged
        #expect(try store.object(forKey: key1) as? Int == 100)
        #expect(try store.object(forKey: key2) as? String == "Alice")
    }

    @Test("Direct dictionary access works")
    func directDictionaryAccess() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"

        // When - set value
        try store.set(42, forKey: key)

        // Then - direct dictionary access returns same value
        #expect(store.underlyingDict[key] as? Int == 42)
    }

    // MARK: - Observable Tests

    @Test("Store conforms to ObservableThrowingKeyValueStoring")
    func storeConformsToObservableThrowingKeyValueStoring() {
        let store = InMemoryObservableThrowingKeyValueStore()
        let conformsToProtocol = store is (any ObservableThrowingKeyValueStoring)
        #expect(conformsToProtocol)
    }

    @Test("Publisher emits for key changes")
    func publisherEmitsForKeyChanges() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"

        var changeCount = 0
        store.updatesPublisher(forKey: key).sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change value (synchronous emission)
        try store.set(42, forKey: key)

        // Then - publisher emits synchronously
        #expect(changeCount == 1)
    }

    @Test("Publisher does not emit for different key")
    func publisherDoesNotEmitForDifferentKey() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key1 = "observableThrowingValue"
        let key2 = "observableThrowingName"

        var changeCount = 0
        store.updatesPublisher(forKey: key1).sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different key
        try store.set("Alice", forKey: key2)

        // Give time for any potential emissions

        // Then - publisher should not emit
        #expect(changeCount == 0)
    }

    @Test("Multiple subscribers to same key")
    func multipleSubscribersToSameKey() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"

        var count1 = 0
        var count2 = 0

        // Given - two subscribers
        store.updatesPublisher(forKey: key).sink { _ in
            count1 += 1
        }.store(in: &cancellables)

        store.updatesPublisher(forKey: key).sink { _ in
            count2 += 1
        }.store(in: &cancellables)

        // When - change value
        try store.set(100, forKey: key)

        // Give time for emissions

        // Then - both subscribers receive update
        #expect(count1 == 1)
        #expect(count2 == 1)
    }

    @Test("Cancelling subscription stops observation")
    func cancellingSubscriptionStopsObservation() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"

        var changeCount = 0
        let cancellable = store.updatesPublisher(forKey: key).sink { _ in
            changeCount += 1
        }

        // Cancel immediately
        cancellable.cancel()

        // When - change value
        try store.set(42, forKey: key)

        // Give time for any potential emissions

        // Then - should not receive updates
        #expect(changeCount == 0)
    }

    @Test("Publisher emits after error throw on get")
    func publisherEmitsAfterErrorThrowOnGet() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        let key = "observableThrowingValue"

        var changeCount = 0
        store.updatesPublisher(forKey: key).sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - set value successfully
        try store.set(42, forKey: key)

        // Then - enable throwing on get
        store.shouldThrowOnGet = true

        // When - try to get (will throw)
        #expect(throws: InMemoryObservableThrowingKeyValueStore.MockError.getError) {
            try store.object(forKey: key)
        }

        // Then - disable throwing and change value again
        store.shouldThrowOnGet = false
        try store.set(100, forKey: key)

        // Then - publisher emitted twice (once for each successful set)
        #expect(changeCount == 2)
    }

    // MARK: - objectWillChange Tests

    @Test("objectWillChange fires for any key change")
    func objectWillChangeFiresForAnyKey() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        var changeCount = 0

        store.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different keys
        try store.set("value1", forKey: "key1")
        try store.set("value2", forKey: "key2")
        try store.set("value3", forKey: "key3")

        // Then - objectWillChange fires for all changes
        #expect(changeCount == 3)
    }

    @Test("objectWillChange fires for remove operations")
    func objectWillChangeFiresForRemove() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        var changeCount = 0

        // Given - value exists
        try store.set("value", forKey: "key")

        store.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - remove value
        try store.removeObject(forKey: "key")

        // Then - objectWillChange fires
        #expect(changeCount == 1)
    }

    @Test("objectWillChange and publisher(for:) both work together")
    func objectWillChangeAndPublisherWorkTogether() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        var objectWillChangeCount = 0
        var publisherCount = 0

        let key = "testKey"

        // Given - subscribe to both
        store.objectWillChange.sink { _ in
            objectWillChangeCount += 1
        }.store(in: &cancellables)

        store.updatesPublisher(forKey: key).sink { _ in
            publisherCount += 1
        }.store(in: &cancellables)

        // When - change the key
        try store.set("value", forKey: key)

        // Then - both fire
        #expect(objectWillChangeCount == 1)
        #expect(publisherCount == 1)

        // When - change a different key
        try store.set("other", forKey: "otherKey")

        // Then - objectWillChange fires but key-specific publisher doesn't
        #expect(objectWillChangeCount == 2)
        #expect(publisherCount == 1)
    }

    @Test("objectWillChange does not fire when throwing on set")
    func objectWillChangeDoesNotFireWhenThrowingOnSet() {
        let store = InMemoryObservableThrowingKeyValueStore()
        var changeCount = 0

        store.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - enable throwing and try to set
        store.shouldThrowOnSet = true
        #expect(throws: InMemoryObservableThrowingKeyValueStore.MockError.setError) {
            try store.set("value", forKey: "key")
        }

        // Then - objectWillChange does not fire (operation failed)
        #expect(changeCount == 0)
    }

    @Test("objectWillChange fires even when throwing on get")
    func objectWillChangeFiresEvenWhenThrowingOnGet() throws {
        let store = InMemoryObservableThrowingKeyValueStore()
        var changeCount = 0

        store.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - set succeeds, then enable throwing on get
        try store.set("value", forKey: "key")
        store.shouldThrowOnGet = true

        // Then - objectWillChange fired once for the successful set
        #expect(changeCount == 1)

        // When - try to get (will throw)
        #expect(throws: InMemoryObservableThrowingKeyValueStore.MockError.getError) {
            try store.object(forKey: "key")
        }

        // Then - objectWillChange doesn't fire again (get doesn't modify)
        #expect(changeCount == 1)
    }
}
