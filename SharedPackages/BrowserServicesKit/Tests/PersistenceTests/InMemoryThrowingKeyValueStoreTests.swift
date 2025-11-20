//
//  InMemoryThrowingKeyValueStoreTests.swift
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
import Persistence
import PersistenceTestingUtils
import Testing

final class InMemoryThrowingKeyValueStoreTests {

    @Test("Store conforms to ThrowingKeyValueStoring")
    func storeConformsToThrowingKeyValueStoring() {
        let store = InMemoryThrowingKeyValueStore()
        let conformsToProtocol = store is ThrowingKeyValueStoring
        #expect(conformsToProtocol)
    }

    @Test("Basic get and set operations")
    func basicGetAndSet() throws {
        let store = InMemoryThrowingKeyValueStore()

        // Given - empty store
        #expect(try store.object(forKey: "testKey") == nil)

        // When - set a value
        try store.set("testValue", forKey: "testKey")

        // Then - value can be retrieved
        #expect(try store.object(forKey: "testKey") as? String == "testValue")
    }

    @Test("Set with different types")
    func setWithDifferentTypes() throws {
        let store = InMemoryThrowingKeyValueStore()

        // Test with Int
        try store.set(42, forKey: "intKey")
        #expect(try store.object(forKey: "intKey") as? Int == 42)

        // Test with String  
        try store.set("test", forKey: "stringKey")
        #expect(try store.object(forKey: "stringKey") as? String == "test")

        // Test with Bool
        try store.set(true, forKey: "boolKey")
        #expect(try store.object(forKey: "boolKey") as? Bool == true)
    }

    @Test("Remove object")
    func removeObject() throws {
        let store = InMemoryThrowingKeyValueStore()

        // Given - value exists
        try store.set("value", forKey: "key")
        #expect(try store.object(forKey: "key") as? String == "value")

        // When - remove the value
        try store.removeObject(forKey: "key")

        // Then - value is removed
        #expect(try store.object(forKey: "key") == nil)
    }

    @Test("Multiple keys work independently")
    func multipleKeysIndependence() throws {
        let store = InMemoryThrowingKeyValueStore()

        // Given - multiple keys with values
        try store.set("value1", forKey: "key1")
        try store.set("value2", forKey: "key2")

        // Then - each key has its own value
        #expect(try store.object(forKey: "key1") as? String == "value1")
        #expect(try store.object(forKey: "key2") as? String == "value2")

        // When - remove one key
        try store.removeObject(forKey: "key1")

        // Then - other key remains
        #expect(try store.object(forKey: "key1") == nil)
        #expect(try store.object(forKey: "key2") as? String == "value2")
    }

    @Test("Get throws when shouldThrowOnGet is enabled")
    func getThrowsWhenEnabled() throws {
        let store = InMemoryThrowingKeyValueStore()

        // Given - store with a value
        try store.set("value", forKey: "key")

        // When - enable throwing on get
        store.shouldThrowOnGet = true

        // Then - get throws error
        #expect(throws: InMemoryThrowingKeyValueStore.MockError.getError) {
            try store.object(forKey: "key")
        }
    }

    @Test("Set throws when shouldThrowOnSet is enabled")
    func setThrowsWhenEnabled() {
        let store = InMemoryThrowingKeyValueStore()

        // When - enable throwing on set
        store.shouldThrowOnSet = true

        // Then - set throws error
        #expect(throws: InMemoryThrowingKeyValueStore.MockError.setError) {
            try store.set("value", forKey: "key")
        }
    }

    @Test("Remove throws when shouldThrowOnRemove is enabled")
    func removeThrowsWhenEnabled() throws {
        let store = InMemoryThrowingKeyValueStore()

        // Given - store with a value
        try store.set("value", forKey: "key")

        // When - enable throwing on remove
        store.shouldThrowOnRemove = true

        // Then - remove throws error
        #expect(throws: InMemoryThrowingKeyValueStore.MockError.removeError) {
            try store.removeObject(forKey: "key")
        }
    }

    @Test("Store works normally when throwing is disabled")
    func normalOperationWhenThrowingDisabled() throws {
        let store = InMemoryThrowingKeyValueStore()

        // Given - throwing flags disabled (default)
        #expect(store.shouldThrowOnGet == false)
        #expect(store.shouldThrowOnSet == false)
        #expect(store.shouldThrowOnRemove == false)

        // When - perform operations
        try store.set("value", forKey: "key")
        let retrieved = try store.object(forKey: "key")
        try store.removeObject(forKey: "key")

        // Then - all operations succeed
        #expect(retrieved as? String == "value")
        #expect(try store.object(forKey: "key") == nil)
    }
}
