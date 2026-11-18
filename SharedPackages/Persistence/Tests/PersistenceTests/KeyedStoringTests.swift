//
//  KeyedStoringTests.swift
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
@_spi(Testing) import Persistence
import Testing

// MARK: - Test Keys

enum TestKeys: String, StorageKeyDescribing {
    case isFirstLaunch = "is-first-launch"
    case refreshInterval
    case theme
    case priority
    case lastModified
    case optionalDate
    case createdAt
    case setting1
    case setting2
    case config1
    case throwingValue
    case throwingName
    case observableThrowingValue
    case observableThrowingName
    case injectionTestValue
    case injectionTestCount
    case throwingTestValue
    // Legacy migration keys
    case newUserName = "userName"
    case newUserAge = "userAge"
    case newValue = "new_value"
    // Assertion test keys
    case invalidKeyWithDots = "user.name.invalid"
    case validUserNameForAssertion = "validUserName"
    case validUserAgeForAssertion = "validUserAge"
}

struct AppSettingsKeys: StoringKeys {
    let isFirstLaunch = StorageKey<Bool>(TestKeys.isFirstLaunch)
    let refreshInterval = StorageKey<Double>(TestKeys.refreshInterval)
}

public enum Theme: String {
    case light
    case dark
    case system
}

public enum Priority: Int {
    case low = 0
    case medium = 1
    case high = 2
}

struct EnumKeys: StoringKeys {
    let theme = StorageKey<Theme>(TestKeys.theme)
    let priority = StorageKey<Priority>(TestKeys.priority)
}

struct DateKeys: StoringKeys {
    let lastModified = StorageKey<Date>(TestKeys.lastModified)
    let optionalDate = StorageKey<Date?>(TestKeys.optionalDate)
    let createdAt = StorageKey<Date>(TestKeys.createdAt)
}

struct AutoObservationKeys1: StoringKeys {
    let setting1 = StorageKey<String>(TestKeys.setting1)
    let setting2 = StorageKey<Int>(TestKeys.setting2)
}

struct AutoObservationKeys2: StoringKeys {
    let config1 = StorageKey<Bool>(TestKeys.config1)
}

// MARK: - Throwing Settings

struct ThrowingKeys: StoringKeys {
    let throwingValue = StorageKey<Int>(TestKeys.throwingValue)
    let throwingName = StorageKey<String>(TestKeys.throwingName)
}

struct ThrowingObservableKeys: StoringKeys {
    let observableThrowingValue = StorageKey<Int>(TestKeys.observableThrowingValue)
    let observableThrowingName = StorageKey<String>(TestKeys.observableThrowingName)
}

// MARK: - Dependency Injection Test Keys

struct InjectionTestKeys: StoringKeys {
    let injectionTestValue = StorageKey<String>(TestKeys.injectionTestValue)
    let injectionTestCount = StorageKey<Int>(TestKeys.injectionTestCount)
}

struct ThrowingInjectionKeys: StoringKeys {
    let throwingTestValue = StorageKey<String>(TestKeys.throwingTestValue)
}

// Custom UserDefaults subclass for test isolation
public final class AppUserDefaults: UserDefaults {}

// Service classes that depend on storage
public final class ServiceWithThrowingStorage {
    let storage: any ObservableThrowingKeyedStoring<ThrowingInjectionKeys>

    init(storage: any ObservableThrowingKeyedStoring<ThrowingInjectionKeys>) {
        self.storage = storage
    }
}

// Test isolation helper - creates unique UserDefaults instances
public final class IsolatedTestUserDefaults: UserDefaults {
    init() {
        super.init(suiteName: "test-\(UUID())")!
    }
}

// MARK: - Main Test Suite

final class KeyedStoringTests {
    // Use UUID to ensure each test instance gets its own isolated UserDefaults
    let suiteName = "KeyedStoringTests-\(UUID().uuidString)"
    var defaults: UserDefaults
    var cancellables = Set<AnyCancellable>()

    init() {
        // Create a fresh UserDefaults for this test instance
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        // Clean up after this specific test
        defaults.removePersistentDomain(forName: suiteName)
        cancellables.removeAll()
    }

    // MARK: - Basic Functionality Tests

    @available(iOS 16, macOS 13, *)
    @Test("KeyedStoring property behavior", .timeLimit(.minutes(1)))
    func keyedStoringPropertyBehavior() {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Check initial state - this should be nil
        let initial = storage.isFirstLaunch
        #expect(initial == nil)

        // Try setting via native method first
        defaults.set(true, forKey: "is-first-launch")
        let afterNativeSet = defaults.object(forKey: "is-first-launch")
        #expect(afterNativeSet as? Bool == true, "Native set should work")

        let viaGetter = storage.isFirstLaunch
        #expect(viaGetter == true, "Getter should return true after native set")

        // Clear it
        defaults.removeObject(forKey: "is-first-launch")
        #expect(storage.isFirstLaunch == nil, "Should be nil after remove")

        // Set via storage property setter
        storage.isFirstLaunch = true

        // Read back via native method
        let viaObject = defaults.object(forKey: "is-first-launch")
        #expect(viaObject as? Bool == true, "Native object should be true after storage set")

        // Read back via storage getter
        let afterSet = storage.isFirstLaunch
        #expect(afterSet == true, "Getter should return true after storage set")
    }

    @available(iOS 16, macOS 13, *)
    @Test("KeyedStoring publishers emit changes", .timeLimit(.minutes(1)))
    func keyedStoringPublishers() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Bool?] = []

        // Given - subscribe to publisher
        storage.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change value multiple times
        storage.isFirstLaunch = true
        storage.isFirstLaunch = false
        storage.isFirstLaunch = nil

        // Then - publisher emits all values
        #expect(receivedValues == [nil, true, false, nil])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher emits on direct key changes", .timeLimit(.minutes(1)))
    func publisherEmitsOnDirectKeyChanges() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Bool?] = []

        // Given - subscribe to publisher
        storage.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change value directly via UserDefaults.set(_:forKey:)
        defaults.set(true, forKey: "is-first-launch")
        defaults.set(false, forKey: "is-first-launch")
        defaults.removeObject(forKey: "is-first-launch")

        // Then - publisher still emits (KVO observes the key)
        #expect(receivedValues == [nil, true, false, nil])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher only emits for relevant property", .timeLimit(.minutes(1)))
    func publisherOnlyEmitsForRelevantProperty() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var emitCount = 0

        // Given - subscribe to isFirstLaunch publisher
        storage.publisher(for: \.isFirstLaunch).sink { _ in
            emitCount += 1
        }.store(in: &cancellables)

        // When - change different property
        storage.refreshInterval = 100.0

        // And - change subscribed property
        storage.isFirstLaunch = true

        // Then - publisher only emits for its property
        #expect(emitCount == 2) // initial + isFirstLaunch change only
    }

    // MARK: - Mock Store Tests

    @available(iOS 16, macOS 13, *)
    @Test("MockKeyValueStore works with KeyedStoring", .timeLimit(.minutes(1)))
    func mockKeyValueStoreWithKeyedStoring() {
        let mockStore = MockKeyValueStore()
        let storage: any KeyedStoring<AppSettingsKeys> = mockStore.keyedStoring()

        // Test that storage works with mock store
        storage.isFirstLaunch = true
        #expect(storage.isFirstLaunch == true)

        storage.refreshInterval = 45.0
        #expect(storage.refreshInterval == 45.0)
    }

    // MARK: - Enum RawRepresentable Tests

    @available(iOS 16, macOS 13, *)
    @Test("Enum with String raw value supports read/write", .timeLimit(.minutes(1)))
    func enumStringRawValueReadWrite() {
        let storage: any KeyedStoring<EnumKeys> = defaults.keyedStoring()

        // Given - enum with String raw value
        storage.theme = .dark

        // Then - stored as raw value
        #expect(storage.theme == Theme.dark)
        #expect(defaults.string(forKey: "theme") == "dark")

        // When - set different value
        storage.theme = .light
        #expect(storage.theme == Theme.light)
    }

    @available(iOS 16, macOS 13, *)
    @Test("String enum publisher emits all changes", .timeLimit(.minutes(1)))
    func stringEnumPublisherEmitsAllChanges() {
        let storage: any ObservableKeyedStoring<EnumKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Theme?] = []

        // Given - subscribe to String enum
        storage.publisher(for: \.theme).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change through multiple values
        storage.theme = .light
        storage.theme = .dark
        storage.theme = .system
        storage.theme = nil
        storage.theme = .light

        // Then - all changes emitted
        #expect(receivedValues == [nil, Theme.light, Theme.dark, Theme.system, nil, Theme.light])
    }

    // MARK: - Date Type Tests

    @available(iOS 16, macOS 13, *)
    @Test("Date type supports read and write", .timeLimit(.minutes(1)))
    func dateTypeReadWrite() {
        let storage: any KeyedStoring<DateKeys> = defaults.keyedStoring()
        let testDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

        // Given - date value set
        storage.lastModified = testDate

        // Then - value is persisted and retrieved
        #expect(storage.lastModified == testDate)
        #expect(defaults.object(forKey: "lastModified") as? Date == testDate)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Date type publisher emits changes", .timeLimit(.minutes(1)))
    func dateTypePublisherEmitsChanges() {
        let storage: any ObservableKeyedStoring<DateKeys> = defaults.observableKeyedStoring()
        var cancellables = Set<AnyCancellable>()
        var receivedDates: [Date?] = []

        // Given - subscribe to date changes
        storage.publisher(for: \.createdAt).sink { date in
            receivedDates.append(date)
        }.store(in: &cancellables)

        let date1 = Date(timeIntervalSince1970: 1_500_000_000)
        let date2 = Date(timeIntervalSince1970: 1_600_000_000)

        // When - dates change
        storage.createdAt = date1
        storage.createdAt = date2
        storage.createdAt = nil

        // Then - all changes emitted
        #expect(receivedDates.count == 4)  // initial nil, date1, date2, nil
        #expect(receivedDates[0] == nil)
        #expect(receivedDates[1] == date1)
        #expect(receivedDates[2] == date2)
        #expect(receivedDates[3] == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Date type with observable objectWillChange", .timeLimit(.minutes(1)))
    @MainActor
    func dateTypeObservableObjectWillChange() {
        let storage: any ObservableKeyedStoring<DateKeys> = defaults.observableKeyedStoring()
        var cancellables = Set<AnyCancellable>()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        let testDate2 = Date(timeIntervalSince1970: 1_800_000_000)

        // When - date changes
        storage.lastModified = testDate
        storage.optionalDate = Date()
        storage.createdAt = testDate2  // Set a value first so remove will fire KVO
        storage.createdAt = nil

        // Then - objectWillChange fires for each change (4 sets including the remove)
        #expect(changeCount == 4)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Multiple Date properties work independently", .timeLimit(.minutes(1)))
    func multipleDatePropertiesIndependent() {
        let storage: any KeyedStoring<DateKeys> = defaults.keyedStoring()

        let date1 = Date(timeIntervalSince1970: 1_500_000_000)
        let date2 = Date(timeIntervalSince1970: 1_600_000_000)
        let date3 = Date(timeIntervalSince1970: 1_700_000_000)

        // Given - multiple dates set
        storage.lastModified = date1
        storage.optionalDate = date2
        storage.createdAt = date3

        // Then - all stored independently
        #expect(storage.lastModified == date1)
        #expect(storage.optionalDate.flatMap { $0 } == date2)
        #expect(storage.createdAt == date3)

        // When - one is changed
        storage.optionalDate = nil

        // Then - others remain unchanged
        #expect(storage.lastModified == date1)
        #expect(storage.optionalDate.flatMap { $0 } == nil)
        #expect(storage.createdAt == date3)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Date type with very recent dates", .timeLimit(.minutes(1)))
    func dateTypeVeryRecentDates() {
        let storage: any KeyedStoring<DateKeys> = defaults.keyedStoring()
        let now = Date()
        let future = Date(timeIntervalSinceNow: 86400) // Tomorrow

        // Given - current and future dates
        storage.lastModified = now
        storage.createdAt = future

        // Then - dates are stored correctly
        #expect(abs(storage.lastModified!.timeIntervalSince(now)) < 0.001) // Within 1ms
        #expect(abs(storage.createdAt!.timeIntervalSince(future)) < 0.001)
    }

    // MARK: - Auto-Observation Tests

    @available(iOS 16, macOS 13, *)
    @Test("Auto-observation triggers for direct key changes", .timeLimit(.minutes(1)))
    @MainActor
    func autoObservationTriggersForDirectKeyChanges() async throws {
        let storage: any ObservableKeyedStoring<AutoObservationKeys1> = defaults.observableKeyedStoring()
        var changeCount = 0

        // Trigger observation setup
        _ = storage.setting1

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - set value directly via UserDefaults
        defaults.set("direct", forKey: "setting1")

        // Then - objectWillChange still fires
        #expect(changeCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Auto-observation with multiple properties", .timeLimit(.minutes(1)))
    @MainActor
    func autoObservationWithMultipleProperties() async throws {
        let storage: any ObservableKeyedStoring<AutoObservationKeys1> = defaults.observableKeyedStoring()
        var changeCount = 0

        // Trigger observation setup
        _ = storage.setting1

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different properties
        storage.setting1 = "changed"
        storage.setting2 = 42

        // Then - objectWillChange fires for both
        #expect(changeCount == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Property publishers emit initial value on subscription", .timeLimit(.minutes(1)))
    func propertyPublishersEmitInitialValueOnSubscription() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Bool?] = []

        // Given - value exists before subscription
        storage.isFirstLaunch = true

        // When - subscribe to publisher
        storage.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value immediately
        #expect(receivedValues == [true])

        // When - change value
        storage.isFirstLaunch = false

        // Then - receives new value
        #expect(receivedValues == [true, false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("objectWillChange does NOT emit on subscription", .timeLimit(.minutes(1)))
    @MainActor
    func objectWillChangeDoesNotEmitOnSubscription() {
        let storage: any ObservableKeyedStoring<AutoObservationKeys1> = defaults.observableKeyedStoring()
        var changeCount = 0

        // Trigger observation setup
        _ = storage.setting1

        // Given - value exists before subscription
        storage.setting1 = "initial"

        // When - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // Then - should NOT have fired (no initial emission)
        #expect(changeCount == 0)

        // When - change value
        storage.setting1 = "changed"

        // Then - fires once for the change
        #expect(changeCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Auto-observation comprehensive isolation", .timeLimit(.minutes(1)))
    @MainActor
    func autoObservationComprehensiveIsolation() {
        // Create 4 different UserDefaults instances
        let suite1a = "test-\(UUID().uuidString)"
        let suite1b = "test-\(UUID().uuidString)"
        let suite2a = "test-\(UUID().uuidString)"
        let suite2b = "test-\(UUID().uuidString)"
        let defaults1a = UserDefaults(suiteName: suite1a)!
        let defaults1b = UserDefaults(suiteName: suite1b)!
        let defaults2a = UserDefaults(suiteName: suite2a)!
        let defaults2b = UserDefaults(suiteName: suite2b)!

        defer {
            defaults1a.removePersistentDomain(forName: suite1a)
            defaults1b.removePersistentDomain(forName: suite1b)
            defaults2a.removePersistentDomain(forName: suite2a)
            defaults2b.removePersistentDomain(forName: suite2b)
        }

        // Create storage instances
        let storage1a: any ObservableKeyedStoring<AutoObservationKeys1> = defaults1a.observableKeyedStoring()
        let storage1b: any ObservableKeyedStoring<AutoObservationKeys1> = defaults1b.observableKeyedStoring()
        let storage2a: any ObservableKeyedStoring<AutoObservationKeys2> = defaults2a.observableKeyedStoring()
        let storage2b: any ObservableKeyedStoring<AutoObservationKeys2> = defaults2b.observableKeyedStoring()

        var change1aCount = 0
        var change1bCount = 0
        var change2aCount = 0
        var change2bCount = 0

        // Trigger observation setup
        _ = storage1a.setting1
        _ = storage1b.setting1
        _ = storage2a.config1
        _ = storage2b.config1

        // Subscribe to all
        storage1a.objectWillChange.sink { _ in change1aCount += 1 }.store(in: &cancellables)
        storage1b.objectWillChange.sink { _ in change1bCount += 1 }.store(in: &cancellables)
        storage2a.objectWillChange.sink { _ in change2aCount += 1 }.store(in: &cancellables)
        storage2b.objectWillChange.sink { _ in change2bCount += 1 }.store(in: &cancellables)

        // When - change settings1a
        storage1a.setting1 = "changed"

        // Then - only settings1a receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 0)
        #expect(change2aCount == 0)
        #expect(change2bCount == 0)

        // When - change settings1b
        storage1b.setting2 = 42

        // Then - only settings1b receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 1)
        #expect(change2aCount == 0)
        #expect(change2bCount == 0)

        // When - change settings2a
        storage2a.config1 = true

        // Then - only settings2a receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 1)
        #expect(change2aCount == 1)
        #expect(change2bCount == 0)

        // When - change settings2b
        storage2b.config1 = false

        // Then - only settings2b receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 1)
        #expect(change2aCount == 1)
        #expect(change2bCount == 1)
    }

    // MARK: - Edge Case Tests

    @available(iOS 16, macOS 13, *)
    @Test("Nil to value to nil cycle works correctly", .timeLimit(.minutes(1)))
    func nilToValueToNilCycle() {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Start with nil
        #expect(storage.refreshInterval == nil)

        // Set to value
        storage.refreshInterval = 30.0
        #expect(storage.refreshInterval == 30.0)

        // Set to different value
        storage.refreshInterval = 60.0
        #expect(storage.refreshInterval == 60.0)

        // Set back to nil
        storage.refreshInterval = nil
        #expect(storage.refreshInterval == nil)

        // Verify key is actually removed
        #expect(defaults.object(forKey: "refreshInterval") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Multiple subscribers receive all updates", .timeLimit(.minutes(1)))
    func multipleSubscribersReceiveAllUpdates() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var subscriber1Values: [Bool?] = []
        var subscriber2Values: [Bool?] = []
        var subscriber3Values: [Bool?] = []

        // Given - three subscribers
        storage.publisher(for: \.isFirstLaunch).sink { value in
            subscriber1Values.append(value)
        }.store(in: &cancellables)

        storage.publisher(for: \.isFirstLaunch).sink { value in
            subscriber2Values.append(value)
        }.store(in: &cancellables)

        storage.publisher(for: \.isFirstLaunch).sink { value in
            subscriber3Values.append(value)
        }.store(in: &cancellables)

        // When - make changes
        storage.isFirstLaunch = true
        storage.isFirstLaunch = false

        // Then - all subscribers receive all updates
        #expect(subscriber1Values == [nil, true, false])
        #expect(subscriber2Values == [nil, true, false])
        #expect(subscriber3Values == [nil, true, false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Thread safety: Concurrent reads work correctly", .timeLimit(.minutes(1)))
    func concurrentReadsWorkCorrectly() async {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Given - set a value
        storage.refreshInterval = 30.0

        // When - read from multiple threads concurrently
        await withTaskGroup(of: Double?.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    return storage.refreshInterval
                }
            }

            // Then - all reads should succeed and return the correct value
            for await value in group {
                #expect(value == 30.0)
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("UserDefaults suite cleanup verifies no persistent domain remains", .timeLimit(.minutes(1)))
    func userDefaultsSuiteCleanupVerification() {
        let testSuiteName = "test-cleanup-\(UUID().uuidString)"

        // Given - create suite and set value
        var testDefaults: UserDefaults? = UserDefaults(suiteName: testSuiteName)
        testDefaults?.set("test", forKey: "key")
        #expect(testDefaults?.object(forKey: "key") as? String == "test")

        // When - remove persistent domain and deallocate
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil

        // Then - recreating suite should have no data
        let newDefaults = UserDefaults(suiteName: testSuiteName)!
        #expect(newDefaults.object(forKey: "key") == nil)

        // Cleanup
        newDefaults.removePersistentDomain(forName: testSuiteName)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Property observation setup is idempotent", .timeLimit(.minutes(1)))
    @MainActor
    func propertyObservationSetupIsIdempotent() {
        let storage: any ObservableKeyedStoring<AutoObservationKeys1> = defaults.observableKeyedStoring()

        // Given - access property multiple times to trigger setup
        _ = storage.setting1
        _ = storage.setting1
        _ = storage.setting1

        var changeCount = 0

        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - modify property
        storage.setting1 = "test"

        // Then - should only receive one notification (not multiple due to multiple setups)
        #expect(changeCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("InMemoryKeyValueStore publisher observes value removal", .timeLimit(.minutes(1)))
    @MainActor
    func inMemoryKeyValueStorePublisherObservesValueRemoval() {
        struct MockStoreKeys: StoringKeys {
            let testValue = StorageKey<Int>(TestKeys.injectionTestCount)
        }

        let mockStore = InMemoryKeyValueStore()
        let storage: any ObservableKeyedStoring<MockStoreKeys> = mockStore.observableKeyedStoring()
        var receivedValues: [Int?] = []

        // Given - value exists before subscription
        storage.testValue = 42

        // When - subscribe to publisher
        storage.publisher(for: \.testValue).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value
        #expect(receivedValues == [42])

        // When - remove value (set to nil)
        storage.testValue = nil

        // Then - receives nil
        #expect(receivedValues == [42, nil])

        // When - set new value after removal
        storage.testValue = 100

        // Then - receives new value
        #expect(receivedValues == [42, nil, 100])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Removing persistent domain while observing does not crash", .timeLimit(.minutes(1)))
    func removingPersistentDomainWhileObservingDoesNotCrash() {
        let tempSuiteName = "test-removal-\(UUID().uuidString)"
        let tempDefaults = UserDefaults(suiteName: tempSuiteName)!
        var tempCancellables = Set<AnyCancellable>()

        // Given - subscribe to changes
        tempDefaults.publisher(for: \.description).sink { _ in
            // Just observe
        }.store(in: &tempCancellables)

        // When - remove persistent domain while observing
        tempDefaults.removePersistentDomain(forName: tempSuiteName)

        // Then - should not crash (test passes if no crash)
        #expect(true)

        // Cleanup
        tempCancellables.removeAll()
    }

    // MARK: - ThrowingValue Tests

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue with mock store that throws on get", .timeLimit(.minutes(1)))
    func throwingValueWithMockStoreThatThrowsOnGet() throws {
        let mockStore = InMemoryThrowingKeyValueStore()
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = mockStore.throwingKeyedStoring()
        mockStore.throwOnRead = NSError(domain: "test", code: 1)

        // Given - mock store throws on get
        // When - get value
        do {
            _ = try storage.value(for: \.throwingValue)
            Issue.record("Should have thrown")
        } catch {
            // Then - error is thrown
            #expect((error as NSError).code == 1)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue with mock store that throws on set", .timeLimit(.minutes(1)))
    func throwingValueWithMockStoreThatThrowsOnSet() throws {
        let mockStore = InMemoryThrowingKeyValueStore()
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = mockStore.throwingKeyedStoring()
        mockStore.throwOnSet = NSError(domain: "test", code: 2)

        // Given - mock store throws on set
        // When - set value
        do {
            try storage.set(42, for: \.throwingValue)
            Issue.record("Should have thrown")
        } catch {
            // Then - error is thrown
            #expect((error as NSError).code == 2)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue multiple properties are independent", .timeLimit(.minutes(1)))
    func throwingValueMultiplePropertiesAreIndependent() throws {
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = defaults.throwingKeyedStoring()

        // When - set both properties
        try storage.set(42, for: \.throwingValue)
        try storage.set("test", for: \.throwingName)

        // Then - both values are independent
        #expect(try storage.value(for: \.throwingValue) == 42)
        #expect(try storage.value(for: \.throwingName) == "test")

        // When - set one to nil
        try storage.set(nil, for: \.throwingValue)

        // Then - other is unaffected
        #expect(try storage.value(for: \.throwingValue) == nil)
        #expect(try storage.value(for: \.throwingName) == "test")
    }

    // MARK: - ObservableThrowingKeyValueStoring Tests

    @available(iOS 16, macOS 13, *)
    @Test("ObservableThrowingKeyValueStoring objectWillChange fires on removal", .timeLimit(.minutes(1)))
    @MainActor
    func observableThrowingValueObjectWillChangeFiresOnRemoval() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()
        var changeCount = 0

        // Given - value exists and subscribed
        try storage.set(42, for: \.observableThrowingValue)

        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - remove value
        try storage.set(nil, for: \.observableThrowingValue)

        // Then - objectWillChange fired
        #expect(changeCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ObservableThrowingKeyValueStoring objectWillChange fires for any key", .timeLimit(.minutes(1)))
    @MainActor
    func observableThrowingValueObjectWillChangeFiresForAnyKey() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different properties
        try storage.set(1, for: \.observableThrowingValue)
        try storage.set("test", for: \.observableThrowingName)

        // Then - objectWillChange fired for both
        #expect(changeCount == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ObservableThrowingKeyValueStoring doesn't fire when get throws", .timeLimit(.minutes(1)))
    func observableThrowingValueDoesntFireWhenGetThrows() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()
        mockStore.throwOnRead = NSError(domain: "test", code: 1)
        var changeCount = 0

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - try to get (will throw)
        do {
            _ = try storage.value(for: \.observableThrowingValue)
        } catch {
            // Expected
        }

        // Then - objectWillChange did not fire
        #expect(changeCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ObservableThrowingKeyValueStoring doesn't fire when set throws", .timeLimit(.minutes(1)))
    func observableThrowingValueDoesntFireWhenSetThrows() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()
        mockStore.throwOnSet = NSError(domain: "test", code: 2)
        var changeCount = 0

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - try to set (will throw)
        do {
            try storage.set(42, for: \.observableThrowingValue)
        } catch {
            // Expected
        }

        // Then - objectWillChange did not fire
        #expect(changeCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue works with different mock stores", .timeLimit(.minutes(1)))
    func throwingValueWorksWithDifferentMockStores() throws {
        let throwingStore = InMemoryThrowingKeyValueStore()
        let throwingStorage: any ThrowingKeyedStoring<ThrowingKeys> = throwingStore.throwingKeyedStoring()
        let observableStore = InMemoryObservableThrowingKeyValueStore()
        let observableStorage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = observableStore.observableThrowingKeyedStoring()

        // When - set values in both
        try throwingStorage.set(42, for: \.throwingValue)
        try observableStorage.set(100, for: \.observableThrowingValue)

        // Then - values are independent
        #expect(try throwingStorage.value(for: \.throwingValue) == 42)
        #expect(try observableStorage.value(for: \.observableThrowingValue) == 100)
    }

    // MARK: - Dependency Injection Tests

    @available(iOS 16, macOS 13, *)
    @Test("UserDefaults can be injected when throwing protocol is required", .timeLimit(.minutes(1)))
    func userDefaultsCanBeInjectedWhenThrowingProtocolRequired() throws {
        // Given - UserDefaults with throwing storage wrapper
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }

        // When - inject throwing storage wrapper into service
        let storage: any ObservableThrowingKeyedStoring<ThrowingInjectionKeys> = appDefaults.observableThrowingKeyedStoring()
        let service = ServiceWithThrowingStorage(storage: storage)

        // Then - throwing operations work
        try service.storage.set("throws-ok", for: \.throwingTestValue)
        let retrieved = try service.storage.value(for: \.throwingTestValue)
        #expect(retrieved == "throws-ok")
    }

    // MARK: - Test Isolation with UserDefaults Subclasses

    @available(iOS 16, macOS 13, *)
    @Test("Isolated UserDefaults subclass provides clean state per test", .timeLimit(.minutes(1)))
    func isolatedUserDefaultsSubclassProvidesCleanStatePerTest() {
        // Given - isolated instance
        let isolated = IsolatedTestUserDefaults()
        let storage: any KeyedStoring<InjectionTestKeys> = isolated.keyedStoring()

        // Then - starts with nil values (clean state)
        #expect(storage.injectionTestValue == nil)
        #expect(storage.injectionTestCount == nil)

        // When - write values
        storage.injectionTestValue = "test-value"
        storage.injectionTestCount = 42

        // Then - values persist in this instance
        #expect(storage.injectionTestValue == "test-value")
        #expect(storage.injectionTestCount == 42)

        // When - create new instance
        let newInstance = IsolatedTestUserDefaults()
        let newStorage: any KeyedStoring<InjectionTestKeys> = newInstance.keyedStoring()

        // Then - new instance has clean state
        #expect(newStorage.injectionTestValue == nil)
        #expect(newStorage.injectionTestCount == nil)
    }

    // MARK: - Legacy Key Migration Tests

    @available(iOS 16, macOS 13, *)
    @Test("Legacy key migration reads from old key when new key is empty", .timeLimit(.minutes(1)))
    func legacyKeyMigrationReadsFromOldKey() {
        struct LegacyKeys: StoringKeys {
            let username = StorageKey<String>(TestKeys.newUserName, migrateLegacyKey: "com.app.legacy.username")
            let userAge = StorageKey<Int>(TestKeys.newUserAge, migrateLegacyKey: "com.app.legacy.age")
        }

        // Given - data stored under legacy dotted keys
        defaults.set("Alice", forKey: "com.app.legacy.username")
        defaults.set(25, forKey: "com.app.legacy.age")

        let storage: any KeyedStoring<LegacyKeys> = defaults.keyedStoring()

        // When - reading through new API
        let name = storage.username
        let age = storage.userAge

        // Then - values are migrated from legacy keys
        #expect(name == "Alice")
        #expect(age == 25)

        // And - legacy dotted keys are removed after migration
        #expect(defaults.string(forKey: "com.app.legacy.username") == nil)
        #expect(defaults.integer(forKey: "com.app.legacy.age") == 0) // UserDefaults returns 0 for missing Int
        #expect(defaults.object(forKey: "com.app.legacy.age") == nil) // Verify it's actually gone

        // And - values are written to new keys during migration
        #expect(defaults.string(forKey: "userName") == "Alice")
        #expect(defaults.integer(forKey: "userAge") == 25)

        // And - subsequent reads work from new keys
        #expect(storage.username == "Alice")
        #expect(storage.userAge == 25)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Legacy key migration prefers new key over legacy key", .timeLimit(.minutes(1)))
    func legacyKeyMigrationPrefersNewKey() {
        struct LegacyKeys: StoringKeys {
            let username = StorageKey<String>(TestKeys.newUserName, migrateLegacyKey: "com.app.legacy.username")
        }

        // Given - data stored under BOTH keys
        defaults.set("LegacyValue", forKey: "com.app.legacy.username")
        defaults.set("NewValue", forKey: "userName")

        let storage: any KeyedStoring<LegacyKeys> = defaults.keyedStoring()

        // When - reading through API
        let name = storage.username

        // Then - new key takes precedence
        #expect(name == "NewValue")

        // And - legacy dotted key is NOT removed (because new key exists)
        #expect(defaults.string(forKey: "com.app.legacy.username") == "LegacyValue")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Legacy key migration works with setting new values", .timeLimit(.minutes(1)))
    func legacyKeyMigrationWritesToNewKey() {
        struct LegacyKeys: StoringKeys {
            let username = StorageKey<String>(TestKeys.newUserName, migrateLegacyKey: "com.app.legacy.username")
        }

        // Given - data stored under legacy dotted key
        defaults.set("OldValue", forKey: "com.app.legacy.username")

        let storage: any KeyedStoring<LegacyKeys> = defaults.keyedStoring()

        // When - writing new value
        storage.username = "UpdatedValue"

        // Then - new value is written to NEW key (no dots), not legacy
        #expect(defaults.string(forKey: "userName") == "UpdatedValue")
        // Legacy dotted key remains unchanged when only writing (not reading first)
        #expect(defaults.string(forKey: "com.app.legacy.username") == "OldValue")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Legacy key migration works with observable storage", .timeLimit(.minutes(1)))
    @MainActor
    func legacyKeyMigrationWithObservableStorage() {
        struct LegacyKeys: StoringKeys {
            let username = StorageKey<String>(TestKeys.newUserName, migrateLegacyKey: "com.app.legacy.username")
        }

        // Given - data stored under legacy dotted key
        defaults.set("LegacyUser", forKey: "com.app.legacy.username")

        let storage: any ObservableKeyedStoring<LegacyKeys> = defaults.observableKeyedStoring()
        var cancellables = Set<AnyCancellable>()
        var receivedValues: [String?] = []

        // When - subscribing to publisher
        storage.publisher(for: \.username).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - initial value comes from legacy dotted key
        #expect(receivedValues.count == 1)
        #expect(receivedValues[0] == "LegacyUser")

        // And - legacy dotted key is removed after initial read
        #expect(defaults.string(forKey: "com.app.legacy.username") == nil)

        // And - value is written to new key during migration
        #expect(defaults.string(forKey: "userName") == "LegacyUser")

        // And - subsequent reads work from new key
        #expect(storage.username == "LegacyUser")
    }

    // MARK: - Dot Assertion Tests

    @available(iOS 16, macOS 13, *)
    @Test("Keys with dots trigger assertion failure", .timeLimit(.minutes(1)))
    func keysWithDotsAssertionFailure() {
        var assertionTriggered = false
        var assertionMessage = ""

        _ = StorageKey<String>(TestKeys.invalidKeyWithDots, assertionHandler: { message in
            assertionTriggered = true
            assertionMessage = message
        })

        #expect(assertionTriggered)
        #expect(!assertionMessage.isEmpty)
        #expect(assertionMessage.contains("user.name.invalid"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keys without dots do not trigger assertion", .timeLimit(.minutes(1)))
    func keysWithoutDotsDoNotTriggerAssertion() {
        var assertionTriggered = false

        // When - creating storage keys without dots
        _ = StorageKey<String>(TestKeys.validUserNameForAssertion, assertionHandler: { _ in
            assertionTriggered = true
        })
        _ = StorageKey<Int>(TestKeys.validUserAgeForAssertion, migrateLegacyKey: "age", assertionHandler: { _ in
            assertionTriggered = true
        })

        // Then - assertion handler was never called
        #expect(!assertionTriggered)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Legacy keys with dots are allowed for migration", .timeLimit(.minutes(1)))
    func legacyKeysWithDotsAreAllowed() {
        var assertionHandlerCalled = false

        // When - creating storage key with legacy key that has dots
        _ = StorageKey<String>(TestKeys.newValue, migrateLegacyKey: "old.value.with.dots", assertionHandler: { _ in
            assertionHandlerCalled = true
        })

        // Then - assertion handler was NOT called (legacy keys with dots are allowed)
        #expect(!assertionHandlerCalled)

        // When - using the keys with storage for actual migration
        defaults.set("legacy-value", forKey: "old.value.with.dots")
        struct LegacyMigrationKeys: StoringKeys {
            let testValue = StorageKey<String>(TestKeys.newValue, migrateLegacyKey: "old.value.with.dots")
        }
        let storage: any KeyedStoring<LegacyMigrationKeys> = defaults.keyedStoring()

        // Then - migration works with dots in legacy key
        #expect(storage.testValue == "legacy-value")
    }
}
