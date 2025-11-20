//
//  ObservableKeyValueStoringTests.swift
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

final class ObservableKeyValueStoringTests {

    private var cancellables: Set<AnyCancellable>
    private var mockStore: MockKeyValueStore

    init() {
        cancellables = []
        mockStore = MockKeyValueStore()
    }

    // MARK: - Basic Observation Tests

    @Test("Publisher emits for key changes")
    func publisherEmitsForKeyChanges() {
        let key = "testKey"

        var changeCount = 0
        mockStore.updatesPublisher(forKey: key).sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change value
        mockStore.set("value", forKey: key)

        // Then - publisher emits synchronously
        #expect(changeCount == 1)
    }

    @Test("Publisher does not emit for different key")
    func publisherDoesNotEmitForDifferentKey() {
        let key1 = "key1"
        let key2 = "key2"

        var changeCount = 0
        mockStore.updatesPublisher(forKey: key1).sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different key
        mockStore.set("value", forKey: key2)

        // Give time for any potential emissions

        // Then - publisher should not emit
        #expect(changeCount == 0)
    }

    @Test("Multiple subscribers to same key")
    func multipleSubscribersToSameKey() {
        let key = "testKey"

        var count1 = 0
        var count2 = 0

        // Given - two subscribers
        mockStore.updatesPublisher(forKey: key).sink { _ in
            count1 += 1
        }.store(in: &cancellables)

        mockStore.updatesPublisher(forKey: key).sink { _ in
            count2 += 1
        }.store(in: &cancellables)

        // When - change value
        mockStore.set("value", forKey: key)

        // Give time for emissions

        // Then - both subscribers receive update
        #expect(count1 == 1)
        #expect(count2 == 1)
    }

    @Test("Cancelling subscription stops observation")
    func cancellingSubscriptionStopsObservation() {
        let key = "testKey"

        var changeCount = 0
        let cancellable = mockStore.updatesPublisher(forKey: key).sink { _ in
            changeCount += 1
        }

        // Cancel immediately
        cancellable.cancel()

        // When - change value
        mockStore.set("value", forKey: key)

        // Give time for any potential emissions

        // Then - should not receive updates
        #expect(changeCount == 0)
    }

    // MARK: - UserDefaults Conformance Tests

    @Test("UserDefaults conforms to ObservableKeyValueStoring")
    func userDefaultsConformsToObservableKeyValueStoring() throws {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conformsToProtocol = defaults is ObservableKeyValueStoring
        #expect(conformsToProtocol)
    }

    @Test("UserDefaults publisher does not emit on subscription")
    func userDefaultsPublisherDoesNotEmitOnSubscription() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "testKey"

        // Given - value already exists
        defaults.set("existingValue", forKey: key)

        var emissionCount = 0

        // When - subscribe to publisher
        defaults.updatesPublisher(forKey: key).sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // Then - publisher does NOT emit the existing value on subscription
        #expect(emissionCount == 0)
        #expect(defaults.string(forKey: key) == "existingValue")
    }

    @Test("UserDefaults publisher emits on change and value is updated")
    func userDefaultsPublisherEmitsOnChange() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "testKey"

        // Set initial value (publisher only emits on changes after subscription)
        defaults.set("initial", forKey: key)

        var emissionCount = 0
        defaults.updatesPublisher(forKey: key).sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // When - change value
        defaults.set("value1", forKey: key)

        // Then - publisher emitted once and value is correct
        #expect(emissionCount == 1)
        #expect(defaults.string(forKey: key) == "value1")

        // When - change value again
        defaults.set("value2", forKey: key)

        // Then - publisher emitted again and value is correct
        #expect(emissionCount == 2)
        #expect(defaults.string(forKey: key) == "value2")

        // When - change value third time
        defaults.set("value3", forKey: key)

        // Then - publisher emitted and value is correct
        #expect(emissionCount == 3)
        #expect(defaults.string(forKey: key) == "value3")
    }

    @Test("UserDefaults publisher only emits for subscribed key")
    func userDefaultsPublisherOnlyEmitsForSubscribedKey() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key1 = "key1"
        let key2 = "key2"

        // Set initial values
        defaults.set("initial1", forKey: key1)
        defaults.set("initial2", forKey: key2)

        var emissionCount = 0
        defaults.updatesPublisher(forKey: key1).sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // When - change subscribed key
        defaults.set("value1", forKey: key1)
        #expect(emissionCount == 1)
        #expect(defaults.string(forKey: key1) == "value1")

        // When - change different key
        defaults.set("value2", forKey: key2)

        // Then - publisher only emits for subscribed key
        #expect(emissionCount == 1)
        #expect(defaults.string(forKey: key2) == "value2")
    }

    @Test("UserDefaults publisher emits on removal")
    func userDefaultsPublisherEmitsOnRemoval() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "testKey"

        // Set initial value
        defaults.set("value", forKey: key)
        #expect(defaults.string(forKey: key) == "value")

        var emissionCount = 0
        defaults.updatesPublisher(forKey: key).sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // When - remove value
        defaults.removeObject(forKey: key)

        // Then - publisher emits and value is removed
        #expect(emissionCount == 1)
        #expect(defaults.string(forKey: key) == nil)

        // When - set value again
        defaults.set("newValue", forKey: key)

        // Then - publisher emits and value is set
        #expect(emissionCount == 2)
        #expect(defaults.string(forKey: key) == "newValue")

        // When - remove again
        defaults.removeObject(forKey: key)

        // Then - publisher emits and value is removed
        #expect(emissionCount == 3)
        #expect(defaults.string(forKey: key) == nil)
    }

    // MARK: - MockKeyValueStore Tests

    @Test("MockKeyValueStore conforms to ObservableKeyValueStoring")
    func mockKeyValueStoreConformsToObservableKeyValueStoring() throws {
        let conformsToProtocol = mockStore is ObservableKeyValueStoring
        #expect(conformsToProtocol)
    }

    @Test("MockKeyValueStore supports multiple keys")
    func mockKeyValueStoreSupportsMultipleKeys() {
        let key1 = "key1"
        let key2 = "key2"

        var key1Changes = 0
        var key2Changes = 0

        mockStore.updatesPublisher(forKey: key1).sink { _ in
            key1Changes += 1
        }.store(in: &cancellables)

        mockStore.updatesPublisher(forKey: key2).sink { _ in
            key2Changes += 1
        }.store(in: &cancellables)

        // When - change both keys
        mockStore.set("value1", forKey: key1)
        mockStore.set("value2", forKey: key2)

        // Give time for emissions

        // Then - each publisher emits only for its key
        #expect(key1Changes == 1)
        #expect(key2Changes == 1)
    }

    // MARK: - objectWillChange Tests

    @Test("objectWillChange fires for any key change")
    func objectWillChangeFiresForAnyKey() {
        var changeCount = 0
        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different keys
        mockStore.set("value1", forKey: "key1")
        mockStore.set("value2", forKey: "key2")
        mockStore.set("value3", forKey: "key3")

        // Then - objectWillChange fires for all changes
        #expect(changeCount == 3)
    }

    @Test("objectWillChange fires for remove operations")
    func objectWillChangeFiresForRemove() {
        var changeCount = 0

        // Given - value exists
        mockStore.set("value", forKey: "key")

        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - remove value
        mockStore.removeObject(forKey: "key")

        // Then - objectWillChange fires
        #expect(changeCount == 1)
    }

    @Test("Multiple subscribers to objectWillChange all receive notifications")
    func multipleSubscribersToObjectWillChange() {
        var count1 = 0
        var count2 = 0
        var count3 = 0

        // Given - multiple subscribers
        mockStore.objectWillChange.sink { _ in count1 += 1 }.store(in: &cancellables)
        mockStore.objectWillChange.sink { _ in count2 += 1 }.store(in: &cancellables)
        mockStore.objectWillChange.sink { _ in count3 += 1 }.store(in: &cancellables)

        // When - change a value
        mockStore.set("value", forKey: "key")

        // Then - all subscribers notified
        #expect(count1 == 1)
        #expect(count2 == 1)
        #expect(count3 == 1)
    }

    @Test("objectWillChange and publisher(for:) both work together")
    func objectWillChangeAndPublisherWorkTogether() {
        var objectWillChangeCount = 0
        var publisherCount = 0

        let key = "testKey"

        // Given - subscribe to both
        mockStore.objectWillChange.sink { _ in
            objectWillChangeCount += 1
        }.store(in: &cancellables)

        mockStore.updatesPublisher(forKey: key).sink { _ in
            publisherCount += 1
        }.store(in: &cancellables)

        // When - change the key
        mockStore.set("value", forKey: key)

        // Then - both fire
        #expect(objectWillChangeCount == 1)
        #expect(publisherCount == 1)

        // When - change a different key
        mockStore.set("other", forKey: "otherKey")

        // Then - objectWillChange fires but key-specific publisher doesn't
        #expect(objectWillChangeCount == 2)
        #expect(publisherCount == 1)
    }

    // MARK: - UserDefaults Dotted Key Tests

    @Test("UserDefaults publisher works with dotted keys")
    func userDefaultsPublisherWorksWithDottedKeys() {
        // Given
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "com.example.dotted.key"
        var receivedCount = 0
        var cancellables = Set<AnyCancellable>()

        // Set initial value
        defaults.set("initial", forKey: key)

        // When - subscribe to dotted key
        defaults.updatesPublisher(forKey: key)
            .sink { _ in
                receivedCount += 1
            }
            .store(in: &cancellables)

        // Then - should not emit on subscription
        #expect(receivedCount == 0)

        // When - change the value
        defaults.set("changed", forKey: key)

        // Then - should emit
        #expect(receivedCount == 1)
    }

    @Test("UserDefaults publisher with dotted keys emits on removal")
    func userDefaultsPublisherWithDottedKeysEmitsOnRemoval() {
        // Given
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "com.example.dotted.key"
        var receivedCount = 0
        var cancellables = Set<AnyCancellable>()

        // Set initial value
        defaults.set("value", forKey: key)

        // When - subscribe
        defaults.updatesPublisher(forKey: key)
            .sink { _ in
                receivedCount += 1
            }
            .store(in: &cancellables)

        // When - remove the value
        defaults.removeObject(forKey: key)

        // Then - should emit
        #expect(receivedCount == 1)
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test("UserDefaults publisher with dotted keys only emits on actual changes")
    func userDefaultsPublisherWithDottedKeysOnlyEmitsOnActualChanges() {
        // Given
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "com.example.dotted.key"
        var receivedCount = 0
        var cancellables = Set<AnyCancellable>()

        // Set initial value
        defaults.set("initial", forKey: key)

        // When - subscribe
        defaults.updatesPublisher(forKey: key)
            .sink { _ in
                receivedCount += 1
            }
            .store(in: &cancellables)

        // When - set to same value (should not emit)
        defaults.set("initial", forKey: key)

        // Then - should not emit
        #expect(receivedCount == 0)

        // When - change to different value
        defaults.set("changed", forKey: key)

        // Then - should emit once
        #expect(receivedCount == 1)

        // When - change other keys (should not trigger this publisher)
        defaults.set("other", forKey: "com.example.other.key")

        // Then - should still be 1
        #expect(receivedCount == 1)
    }

    @Test("UserDefaults publisher with dotted keys handles nil to value transition")
    func userDefaultsPublisherWithDottedKeysHandlesNilToValue() {
        // Given
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "com.example.dotted.key"
        var receivedCount = 0
        var cancellables = Set<AnyCancellable>()

        // Ensure key doesn't exist
        defaults.removeObject(forKey: key)

        // When - subscribe
        defaults.updatesPublisher(forKey: key)
            .sink { _ in
                receivedCount += 1
            }
            .store(in: &cancellables)

        // When - set value (nil -> value)
        defaults.set("value", forKey: key)

        // Then - should emit
        #expect(receivedCount == 1)

        // When - remove value (value -> nil)
        defaults.removeObject(forKey: key)

        // Then - should emit again
        #expect(receivedCount == 2)
    }
}
