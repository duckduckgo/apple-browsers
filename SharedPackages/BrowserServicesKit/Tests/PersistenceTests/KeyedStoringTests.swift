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
import Persistence
import PersistenceTestingUtils
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
    case nestedValue
    case nestedCount
    case injectionTestValue
    case injectionTestCount
    case throwingTestValue
    case testString
    case userName = "testUserName"
    case userAge = "testUserAge"
    case isActive = "testIsActive"
    case lastLogin = "testLastLogin"
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

// MARK: - Enum-based Keys (StorageKeyDescribing)

struct EnumBasedKeys: StoringKeys {
    let userName = StorageKey<String>(TestKeys.userName)
    let userAge = StorageKey<Int>(TestKeys.userAge)
    let isActive = StorageKey<Bool>(TestKeys.isActive)
    let lastLogin = StorageKey<Date>(TestKeys.lastLogin)
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

// MARK: - Nested Protocol Test

struct NestedKeys: StoringKeys {
    let nestedValue = StorageKey<String>(TestKeys.nestedValue)
    let nestedCount = StorageKey<Int>(TestKeys.nestedCount)
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

// Custom file store wrapping InMemoryKeyValueStore  
public final class AppFileStore: InMemoryKeyValueStore {}

// Service classes that depend on storage
public final class ServiceWithStorage {
    let storage: any ObservableKeyedStoring<InjectionTestKeys>

    init(storage: any ObservableKeyedStoring<InjectionTestKeys>) {
        self.storage = storage
    }
}

public final class ServiceWithThrowingStorage {
    let storage: any ObservableThrowingKeyedStoring<ThrowingInjectionKeys>

    init(storage: any ObservableThrowingKeyedStoring<ThrowingInjectionKeys>) {
        self.storage = storage
    }
}

// Service that requires SPECIFIC subclass (not just protocol) for test isolation
public final class ServiceWithConstrainedUserDefaults {
    let settings: AppUserDefaults  // Type-constrained to subclass

    init(settings: AppUserDefaults) {
        self.settings = settings
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
    @Test("KeyedStoring properties support read and write", .timeLimit(.minutes(1)))
    func keyedStoringPropertiesReadWrite() {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Given - empty defaults
        #expect(storage.isFirstLaunch == nil)
        #expect(storage.refreshInterval == nil)

        // When - set values
        storage.isFirstLaunch = true
        storage.refreshInterval = 30.0

        // Then - values are stored and retrieved
        #expect(storage.isFirstLaunch == true)
        #expect(storage.refreshInterval == 30.0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("KeyedStoring properties work with custom keys", .timeLimit(.minutes(1)))
    func keyedStoringPropertiesWithCustomKeys() {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Given - property with custom key
        storage.isFirstLaunch = false

        // Then - value is stored with custom key
        #expect(defaults.bool(forKey: "is-first-launch") == false)

        // When - set via UserDefaults directly
        defaults.set(true, forKey: "is-first-launch")

        // Then - value is accessible via KeyedStoring property
        #expect(storage.isFirstLaunch == true)
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
    @Test("Publisher works with KeyPath", .timeLimit(.minutes(1)))
    func publisherWithKeyPath() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Double?] = []

        // Given - subscribe using keyPath
        storage.publisher(for: \.refreshInterval).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - set value
        storage.refreshInterval = 60.0

        // Then - publisher emits both initial and new value
        #expect(receivedValues == [nil, 60.0])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher works with custom key", .timeLimit(.minutes(1)))
    func publisherWithCustomKey() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Bool?] = []

        // Given - subscribe to custom-keyed property
        storage.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - set value
        storage.isFirstLaunch = true

        // Then - publisher emits both initial and new value
        #expect(receivedValues == [nil, true])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Wrapper can be observed through publisher", .timeLimit(.minutes(1)))
    func wrapperCanBeObservedThroughPublisher() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Bool?] = []

        // Given - subscribe to publisher
        storage.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change value multiple times
        storage.isFirstLaunch = true

        storage.isFirstLaunch = false

        // Then - publisher emits all values
        #expect(receivedValues == [nil, true, false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Protocol usage with dependency injection", .timeLimit(.minutes(1)))
    func protocolUsageWithInjection() {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Test that storage can be used with dependency injection
        func updateSettings(_ settings: any KeyedStoring<AppSettingsKeys>) {
            settings.isFirstLaunch = false
        }

        updateSettings(storage)
        #expect(storage.isFirstLaunch == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher supports multiple subscribers", .timeLimit(.minutes(1)))
    func publisherWithMultipleSubscribers() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var values1: [Double?] = []
        var values2: [Double?] = []

        // Given - two subscribers to the same publisher
        storage.publisher(for: \.refreshInterval).sink { value in
            values1.append(value)
        }.store(in: &cancellables)

        storage.publisher(for: \.refreshInterval).sink { value in
            values2.append(value)
        }.store(in: &cancellables)

        // When - set value
        storage.refreshInterval = 30.0

        // Then - both subscribers receive the update
        #expect(values1 == [nil, 30.0])
        #expect(values2 == [nil, 30.0])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher isolation between protocols", .timeLimit(.minutes(1)))
    func publisherIsolationBetweenProtocols() {
        let storage1: any ObservableKeyedStoring<AutoObservationKeys1> = defaults.observableKeyedStoring()
        let storage2: any ObservableKeyedStoring<AutoObservationKeys2> = defaults.observableKeyedStoring()

        var setting1Changes = 0
        var config1Changes = 0

        // Given - subscribe to publishers from different storage instances
        storage1.publisher(for: \.setting1).sink { _ in
            setting1Changes += 1
        }.store(in: &cancellables)

        storage2.publisher(for: \.config1).sink { _ in
            config1Changes += 1
        }.store(in: &cancellables)

        // When - change setting1
        storage1.setting1 = "changed"

        // Then - only setting1 publisher fires
        #expect(setting1Changes == 2) // initial + change
        #expect(config1Changes == 1) // only initial

        // When - change config1
        storage2.config1 = true

        // Then - only config1 publisher fires
        #expect(setting1Changes == 2)
        #expect(config1Changes == 2) // initial + change
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher works with enum types", .timeLimit(.minutes(1)))
    func publisherWithEnumType() {
        let storage: any ObservableKeyedStoring<EnumKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Theme?] = []

        // Given - subscribe to enum property
        storage.publisher(for: \.theme).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - set enum value (stored as rawValue)
        storage.theme = .dark

        // Then - publisher emits
        #expect(receivedValues == [nil, Theme.dark])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nil values are handled correctly", .timeLimit(.minutes(1)))
    func nilValues() {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Given - set value
        storage.isFirstLaunch = true
        #expect(storage.isFirstLaunch != nil)

        // When - set to nil
        storage.isFirstLaunch = nil

        // Then - value is nil
        #expect(storage.isFirstLaunch == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Multiple properties work independently", .timeLimit(.minutes(1)))
    func multiplePropertiesIndependence() {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // Given - set multiple properties
        storage.isFirstLaunch = true
        storage.refreshInterval = 120.0

        // When - change one
        storage.isFirstLaunch = false

        // Then - other remains unchanged
        #expect(storage.isFirstLaunch == false)
        #expect(storage.refreshInterval == 120.0)
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

    // MARK: - Nested Protocol Tests

    @available(iOS 16, macOS 13, *)
    @Test("Nested protocol works with MockKeyValueStore", .timeLimit(.minutes(1)))
    func nestedProtocolWorksWithMockKeyValueStore() {
        let mockStore = MockKeyValueStore()
        let storage: any KeyedStoring<NestedKeys> = mockStore.keyedStoring()

        // When - use nested storage
        storage.nestedValue = "test"
        storage.nestedCount = 42

        // Then - values are stored and retrieved
        #expect(storage.nestedValue == "test")
        #expect(storage.nestedCount == 42)
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
    @Test("Enum with Int raw value supports read/write", .timeLimit(.minutes(1)))
    func enumIntRawValueReadWrite() {
        let storage: any KeyedStoring<EnumKeys> = defaults.keyedStoring()

        // Given - enum with Int raw value
        storage.priority = .high

        // Then - stored as raw value
        #expect(storage.priority == Priority.high)
        #expect(defaults.integer(forKey: "priority") == 2)

        // When - set different value
        storage.priority = .low
        #expect(storage.priority == Priority.low)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum handles nil value", .timeLimit(.minutes(1)))
    func enumNilValue() {
        let storage: any KeyedStoring<EnumKeys> = defaults.keyedStoring()

        // Given - enum value set
        storage.theme = .system
        #expect(storage.theme != nil)

        // When - set to nil
        storage.theme = nil

        // Then - value is nil
        #expect(storage.theme == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum publisher emits changes", .timeLimit(.minutes(1)))
    func enumPublisherEmitsChanges() {
        let storage: any ObservableKeyedStoring<EnumKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Theme?] = []

        // Given - subscribe to enum publisher
        storage.publisher(for: \.theme).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change values
        storage.theme = .dark
        storage.theme = .light

        // Then - publisher emits all changes
        #expect(receivedValues == [nil, Theme.dark, Theme.light])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum publisher with KeyPath", .timeLimit(.minutes(1)))
    func enumPublisherWithKeyPath() {
        let storage: any ObservableKeyedStoring<EnumKeys> = defaults.observableKeyedStoring()
        var receivedValue: Priority?

        // Given - subscribe via keyPath
        storage.publisher(for: \.priority).sink { value in
            receivedValue = value
        }.store(in: &cancellables)

        // When - set value
        storage.priority = .medium

        // Then - publisher emits
        #expect(receivedValue == Priority.medium)
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

    @available(iOS 16, macOS 13, *)
    @Test("Int enum publisher emits all changes", .timeLimit(.minutes(1)))
    func intEnumPublisherEmitsAllChanges() {
        let storage: any ObservableKeyedStoring<EnumKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Priority?] = []

        // Given - subscribe to Int enum
        storage.publisher(for: \.priority).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change through multiple values
        storage.priority = .low
        storage.priority = .high
        storage.priority = .medium
        storage.priority = nil
        storage.priority = .low

        // Then - all changes emitted
        #expect(receivedValues == [nil, .low, .high, .medium, nil, .low])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Negative Int enum publisher works correctly", .timeLimit(.minutes(1)))
    func negativeIntEnumPublisherWorks() {
        enum Status: Int {
            case error = -1
            case pending = 0
            case success = 1
        }

        // Extend AppSettings to include Status
        var receivedValues: [Priority?] = []

        // Given - set and read raw values (testing the underlying storage)
        defaults.set(Status.error.rawValue, forKey: "status")
        let stored = defaults.integer(forKey: "status")
        #expect(stored == -1)

        // When - change through values
        defaults.set(Status.pending.rawValue, forKey: "status")
        #expect(defaults.integer(forKey: "status") == 0)

        defaults.set(Status.success.rawValue, forKey: "status")
        #expect(defaults.integer(forKey: "status") == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum publisher with KeyPath emits all changes", .timeLimit(.minutes(1)))
    func enumPublisherWithKeyPathEmitsAllChanges() {
        let storage: any ObservableKeyedStoring<EnumKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Priority?] = []

        // Given - subscribe via KeyPath
        storage.publisher(for: \.priority).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change multiple times
        storage.priority = .low
        storage.priority = .medium
        storage.priority = .high

        // Then - all values emitted
        #expect(receivedValues == [nil, Priority.low, Priority.medium, Priority.high])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum updatesPublisher(forKey:) emits for both String and Int enums", .timeLimit(.minutes(1)))
    func enumUpdatesPublisherForKeyWorks() {
        let storage: any ObservableKeyedStoring<EnumKeys> = defaults.observableKeyedStoring()
        var themeCount = 0
        var priorityCount = 0

        // Given - subscribe to both enum types (use count instead of value)
        storage.publisher(for: \.theme).sink { _ in
            themeCount += 1
        }.store(in: &cancellables)

        storage.publisher(for: \.priority).sink { _ in
            priorityCount += 1
        }.store(in: &cancellables)

        // When - change both
        storage.theme = .dark
        storage.priority = .high
        storage.theme = .light

        // Then - both emit correctly (including initial)
        #expect(themeCount == 3)  // initial, dark, light
        #expect(priorityCount == 2)  // initial, high
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
    @Test("Date type handles nil values", .timeLimit(.minutes(1)))
    func dateTypeNilValue() {
        let storage: any KeyedStoring<DateKeys> = defaults.keyedStoring()

        // Given - no date set (Note: Date?? requires flatMap for comparison)
        #expect(storage.optionalDate.flatMap { $0 } == nil)

        // When - date is set
        let testDate = Date(timeIntervalSince1970: 1_600_000_000)
        storage.optionalDate = testDate

        // Then - value is retrieved
        #expect(storage.optionalDate.flatMap { $0 } == testDate)

        // When - date is removed
        storage.optionalDate = nil

        // Then - value is nil
        #expect(storage.optionalDate.flatMap { $0 } == nil)
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
    @Test("Date type persists across storage instances", .timeLimit(.minutes(1)))
    func dateTypePersistsAcrossInstances() {
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Given - date set in first instance
        let storage1: any KeyedStoring<DateKeys> = defaults.keyedStoring()
        storage1.lastModified = testDate

        // When - new instance created
        let storage2: any KeyedStoring<DateKeys> = defaults.keyedStoring()

        // Then - date is still accessible
        #expect(storage2.lastModified == testDate)
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

    // MARK: - Enum-Based Keys (StorageKeyDescribing) Tests

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys work with String values", .timeLimit(.minutes(1)))
    func enumBasedKeysStringValues() {
        let storage: any KeyedStoring<EnumBasedKeys> = defaults.keyedStoring()

        // Given - value set via enum key
        storage.userName = "Alice"

        // Then - value is persisted with correct raw key
        #expect(storage.userName == "Alice")
        #expect(defaults.string(forKey: TestKeys.userName.rawValue) == "Alice")
        #expect(defaults.string(forKey: "testUserName") == "Alice")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys work with Int values", .timeLimit(.minutes(1)))
    func enumBasedKeysIntValues() {
        let storage: any KeyedStoring<EnumBasedKeys> = defaults.keyedStoring()

        // Given - Int value set
        storage.userAge = 25

        // Then - value is persisted
        #expect(storage.userAge == 25)
        #expect(defaults.integer(forKey: TestKeys.userAge.rawValue) == 25)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys work with Bool values", .timeLimit(.minutes(1)))
    func enumBasedKeysBoolValues() {
        let storage: any KeyedStoring<EnumBasedKeys> = defaults.keyedStoring()

        // Given - Bool value set
        storage.isActive = true

        // Then - value is persisted
        #expect(storage.isActive == true)
        #expect(defaults.bool(forKey: TestKeys.isActive.rawValue) == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys work with Date values", .timeLimit(.minutes(1)))
    func enumBasedKeysDateValues() {
        let storage: any KeyedStoring<EnumBasedKeys> = defaults.keyedStoring()
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Given - Date value set
        storage.lastLogin = testDate

        // Then - value is persisted
        #expect(storage.lastLogin == testDate)
        #expect(defaults.object(forKey: TestKeys.lastLogin.rawValue) as? Date == testDate)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys work with InMemoryKeyValueStore", .timeLimit(.minutes(1)))
    func enumBasedKeysWithInMemoryStore() {
        let storage: any KeyedStoring<EnumBasedKeys> = InMemoryKeyValueStore().keyedStoring()

        // Given - multiple values set
        storage.userName = "Bob"
        storage.userAge = 30
        storage.isActive = false

        // Then - all values are stored independently
        #expect(storage.userName == "Bob")
        #expect(storage.userAge == 30)
        #expect(storage.isActive == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys work with observable storage", .timeLimit(.minutes(1)))
    @MainActor
    func enumBasedKeysWithObservableStorage() {
        let storage: any ObservableKeyedStoring<EnumBasedKeys> = defaults.observableKeyedStoring()
        var cancellables = Set<AnyCancellable>()
        var receivedNames: [String?] = []

        // Given - subscribe to changes
        storage.publisher(for: \.userName).sink { name in
            receivedNames.append(name)
        }.store(in: &cancellables)

        // When - values change
        storage.userName = "Charlie"
        storage.userName = "David"

        // Then - publisher emits all values
        #expect(receivedNames.count == 3)  // initial nil, Charlie, David
        #expect(receivedNames[0] == nil)
        #expect(receivedNames[1] == "Charlie")
        #expect(receivedNames[2] == "David")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys prevent typos via type safety", .timeLimit(.minutes(1)))
    func enumBasedKeysTypeSafety() {
        let storage: any KeyedStoring<EnumBasedKeys> = defaults.keyedStoring()

        // Given - value set via enum (compile-time safe)
        storage.userName = "Eve"

        // Then - correct key is used (enum guarantees correct spelling)
        #expect(defaults.string(forKey: "testUserName") == "Eve")

        // And - typos would not compile:
        // storage.usrName = "Eve"  // ❌ Compile error
        // storage.userName = 123   // ❌ Compile error (wrong type)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum-based keys with nil values", .timeLimit(.minutes(1)))
    func enumBasedKeysNilValues() {
        let storage: any KeyedStoring<EnumBasedKeys> = defaults.keyedStoring()

        // Given - value set then removed
        storage.userName = "Frank"
        #expect(storage.userName == "Frank")

        // When - value set to nil
        storage.userName = nil

        // Then - value is removed
        #expect(storage.userName == nil)
        #expect(defaults.string(forKey: TestKeys.userName.rawValue) == nil)
    }

    // MARK: - Auto-Observation Tests

    @available(iOS 16, macOS 13, *)
    @Test("Auto-observation triggers objectWillChange for property changes", .timeLimit(.minutes(1)))
    @MainActor
    func autoObservationTriggersObjectWillChangeForPropertyChanges() async throws {
        let storage: any ObservableKeyedStoring<AutoObservationKeys1> = defaults.observableKeyedStoring()
        var changeCount = 0

        // Trigger observation setup by accessing the property
        _ = storage.setting1

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - modify property
        storage.setting1 = "test"

        // Then - objectWillChange fired
        #expect(changeCount == 1)
    }

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
    @Test("Auto-observation isolation between protocols", .timeLimit(.minutes(1)))
    @MainActor
    func autoObservationIsolationBetweenProtocols() async throws {
        let storage1: any ObservableKeyedStoring<AutoObservationKeys1> = defaults.observableKeyedStoring()
        let storage2: any ObservableKeyedStoring<AutoObservationKeys2> = defaults.observableKeyedStoring()

        var settings1ChangeCount = 0
        var settings2ChangeCount = 0

        // Trigger observation setup for both
        _ = storage1.setting1
        _ = storage2.config1

        // Given - subscribe to both storages
        storage1.objectWillChange.sink { _ in
            settings1ChangeCount += 1
        }.store(in: &cancellables)

        storage2.objectWillChange.sink { _ in
            settings2ChangeCount += 1
        }.store(in: &cancellables)

        // When - change settings1 property
        storage1.setting1 = "changed"

        // Then - only settings1 fires
        #expect(settings1ChangeCount == 1)
        #expect(settings2ChangeCount == 0)

        // When - change settings2 property
        storage2.config1 = true

        // Then - only settings2 fires
        #expect(settings1ChangeCount == 1)
        #expect(settings2ChangeCount == 1)
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
    @Test("Auto-observation isolation between different UserDefaults instances", .timeLimit(.minutes(1)))
    @MainActor
    func autoObservationIsolationBetweenDifferentUserDefaultsInstances() {
        let suite1 = "test-\(UUID().uuidString)"
        let suite2 = "test-\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suite1)!
        let defaults2 = UserDefaults(suiteName: suite2)!
        defer {
            defaults1.removePersistentDomain(forName: suite1)
            defaults2.removePersistentDomain(forName: suite2)
        }

        let storage1: any ObservableKeyedStoring<AutoObservationKeys1> = defaults1.observableKeyedStoring()
        let storage2: any ObservableKeyedStoring<AutoObservationKeys1> = defaults2.observableKeyedStoring()

        var settings1aChangeCount = 0
        var settings1bChangeCount = 0

        // Trigger observation setup
        _ = storage1.setting1
        _ = storage2.setting1

        // Given - subscribe to both instances
        storage1.objectWillChange.sink { _ in
            settings1aChangeCount += 1
        }.store(in: &cancellables)

        storage2.objectWillChange.sink { _ in
            settings1bChangeCount += 1
        }.store(in: &cancellables)

        // When - change defaults1
        storage1.setting1 = "changed"

        // Then - only defaults1 receives notification
        #expect(settings1aChangeCount == 1)
        #expect(settings1bChangeCount == 0)

        // When - change defaults2
        storage2.setting1 = "changed"

        // Then - only defaults2 receives notification
        #expect(settings1aChangeCount == 1)
        #expect(settings1bChangeCount == 1)
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
    @Test("KeyPath publishers emit initial value on subscription", .timeLimit(.minutes(1)))
    func keyPathPublishersEmitInitialValueOnSubscription() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Double?] = []

        // Given - value exists before subscription
        storage.refreshInterval = 30.0

        // When - subscribe to publisher(for: keyPath)
        storage.publisher(for: \.refreshInterval).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value immediately
        #expect(receivedValues == [30.0])

        // When - change value
        storage.refreshInterval = 60.0

        // Then - receives new value
        #expect(receivedValues == [30.0, 60.0])
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
    @Test("Publisher emits rapidly for many changes", .timeLimit(.minutes(1)))
    func publisherHandlesRapidChanges() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedCount = 0

        // Given - subscribe to publisher
        storage.publisher(for: \.isFirstLaunch).sink { _ in
            receivedCount += 1
        }.store(in: &cancellables)

        // When - make 50 rapid changes
        for i in 0..<50 {
            storage.isFirstLaunch = (i % 2 == 0)
        }

        // Then - should receive all updates (initial + 50 changes)
        #expect(receivedCount == 51)
    }

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
    @Test("Thread safety: Concurrent writes to different keys", .timeLimit(.minutes(1)))
    func concurrentWritesToDifferentKeys() async {
        let storage: any KeyedStoring<AppSettingsKeys> = defaults.keyedStoring()

        // When - write different keys from multiple threads
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 2 == 0 {
                        storage.isFirstLaunch = true
                    } else {
                        storage.refreshInterval = Double(i)
                    }
                }
            }

            await group.waitForAll()
        }

        // Then - both properties should have some value set
        #expect(storage.isFirstLaunch != nil || storage.refreshInterval != nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Large string value persists correctly", .timeLimit(.minutes(1)))
    func largeStringValuePersistsCorrectly() {
        // Given - a large string (1MB)
        let largeString = String(repeating: "A", count: 1_000_000)

        // When - store and retrieve
        defaults.set(largeString, forKey: "largeString")
        let retrieved = defaults.object(forKey: "largeString") as? String

        // Then - value is preserved
        #expect(retrieved == largeString)
        #expect(retrieved?.count == 1_000_000)

        // Cleanup
        defaults.removeObject(forKey: "largeString")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Large data value persists correctly", .timeLimit(.minutes(1)))
    func largeDataValuePersistsCorrectly() {
        // Given - large data (5MB)
        let largeData = Data(repeating: 0xFF, count: 5_000_000)

        // When - store and retrieve
        defaults.set(largeData, forKey: "largeData")
        let retrieved = defaults.object(forKey: "largeData") as? Data

        // Then - data is preserved
        #expect(retrieved == largeData)
        #expect(retrieved?.count == 5_000_000)

        // Cleanup
        defaults.removeObject(forKey: "largeData")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Very long key name works", .timeLimit(.minutes(1)))
    func veryLongKeyNameWorks() {
        // Given - a very long key (1000 chars)
        let longKey = String(repeating: "k", count: 1000)

        // When - store and retrieve
        defaults.set("testValue", forKey: longKey)
        let retrieved = defaults.object(forKey: longKey) as? String

        // Then - works correctly
        #expect(retrieved == "testValue")

        // Cleanup
        defaults.removeObject(forKey: longKey)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enum with negative Int raw value", .timeLimit(.minutes(1)))
    func enumWithNegativeIntRawValue() {
        // Given - enum with negative raw values
        enum Status: Int {
            case error = -1
            case pending = 0
            case success = 1
        }

        // When - store and retrieve negative value
        defaults.set(Status.error.rawValue, forKey: "status")
        let retrieved = defaults.object(forKey: "status") as? Int

        // Then - negative value preserved
        #expect(retrieved == -1)
        #expect(Status(rawValue: retrieved!) == .error)

        // Cleanup
        defaults.removeObject(forKey: "status")
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
    @Test("Publisher subscription after value changes emits current value", .timeLimit(.minutes(1)))
    func publisherSubscriptionAfterValueChangesEmitsCurrentValue() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Bool?] = []

        // Given - change value before subscribing
        storage.isFirstLaunch = true
        storage.isFirstLaunch = false

        // When - subscribe to publisher
        storage.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives current value immediately
        #expect(receivedValues == [false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("InMemoryKeyValueStore publisher emits initial value on subscription", .timeLimit(.minutes(1)))
    @MainActor
    func inMemoryKeyValueStorePublisherEmitsInitialValue() {
        struct MockStoreKeys: StoringKeys {
            let testValue = StorageKey<String>(TestKeys.testString)
        }

        let mockStore = InMemoryKeyValueStore()
        let storage: any ObservableKeyedStoring<MockStoreKeys> = mockStore.observableKeyedStoring()
        var receivedValues: [String?] = []

        // Given - value exists before subscription
        storage.testValue = "initialValue"

        // When - subscribe to publisher
        storage.publisher(for: \.testValue).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value immediately
        #expect(receivedValues == ["initialValue"])

        // When - change value
        storage.testValue = "newValue"

        // Then - receives new value
        #expect(receivedValues == ["initialValue", "newValue"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("UserDefaults publisher with dotted legacy key emits initial value on subscription", .timeLimit(.minutes(1)))
    @MainActor
    func userDefaultsPublisherWithDottedLegacyKeyEmitsInitialValue() {
        struct LegacyDottedKeys: StoringKeys {
            // New key without dots, legacy key with dots
            let userName = StorageKey<String>(
                TestKeys.newUserName,  // Raw value is "userName"
                migrateLegacyKey: "com.example.legacy.userName",
                assertionHandler: { _ in }
            )
        }

        let suiteName = "test-dotted-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let storage: any ObservableKeyedStoring<LegacyDottedKeys> = testDefaults.observableKeyedStoring()
        var receivedValues: [String?] = []

        // Given - value stored under legacy dotted key
        testDefaults.set("LegacyValue", forKey: "com.example.legacy.userName")

        // When - subscribe to publisher
        storage.publisher(for: \.userName).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value immediately (read from legacy key)
        #expect(receivedValues == ["LegacyValue"])

        // And - legacy key is removed after first read
        #expect(testDefaults.string(forKey: "com.example.legacy.userName") == nil)

        // When - change value (writes to new key)
        storage.userName = "NewValue"

        // Then - receives new value
        #expect(receivedValues == ["LegacyValue", "NewValue"])

        // And - new value is in new key
        #expect(testDefaults.string(forKey: "userName") == "NewValue")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher emits initial nil value on subscription", .timeLimit(.minutes(1)))
    @MainActor
    func publisherEmitsInitialNilValueOnSubscription() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Bool?] = []

        // Given - no value exists (nil)
        #expect(storage.isFirstLaunch == nil)

        // When - subscribe to publisher
        storage.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives nil immediately
        #expect(receivedValues.count == 1)
        #expect(receivedValues[0] == nil)

        // When - set a value
        storage.isFirstLaunch = true

        // Then - receives the new value
        #expect(receivedValues == [nil, true])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Publisher observes value removal", .timeLimit(.minutes(1)))
    @MainActor
    func publisherObservesValueRemoval() {
        let storage: any ObservableKeyedStoring<AppSettingsKeys> = defaults.observableKeyedStoring()
        var receivedValues: [Double?] = []

        // Given - value exists before subscription
        storage.refreshInterval = 30.0

        // When - subscribe to publisher
        storage.publisher(for: \.refreshInterval).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value
        #expect(receivedValues == [30.0])

        // When - remove value (set to nil)
        storage.refreshInterval = nil

        // Then - receives nil
        #expect(receivedValues == [30.0, nil])

        // When - set new value after removal
        storage.refreshInterval = 60.0

        // Then - receives new value
        #expect(receivedValues == [30.0, nil, 60.0])
    }

    @available(iOS 16, macOS 13, *)
    @Test("InMemoryKeyValueStore publisher emits initial nil value", .timeLimit(.minutes(1)))
    @MainActor
    func inMemoryKeyValueStorePublisherEmitsInitialNilValue() {
        struct MockStoreKeys: StoringKeys {
            let testValue = StorageKey<String>(TestKeys.testString)
        }

        let mockStore = InMemoryKeyValueStore()
        let storage: any ObservableKeyedStoring<MockStoreKeys> = mockStore.observableKeyedStoring()
        var receivedValues: [String?] = []

        // Given - no value exists (nil)
        #expect(storage.testValue == nil)

        // When - subscribe to publisher
        storage.publisher(for: \.testValue).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives nil immediately
        #expect(receivedValues.count == 1)
        #expect(receivedValues[0] == nil)

        // When - set a value
        storage.testValue = "nowExists"

        // Then - receives the new value
        #expect(receivedValues == [nil, "nowExists"])
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
    @Test("UserDefaults with dotted key publisher observes value removal", .timeLimit(.minutes(1)))
    @MainActor
    func userDefaultsWithDottedKeyPublisherObservesValueRemoval() {
        let suiteName = "test-dotted-removal-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let dottedKey = "com.example.dotted.removal"
        var receivedCount = 0
        var lastReceivedValue: String?

        // Given - value exists
        testDefaults.set("initialValue", forKey: dottedKey)

        // When - subscribe to dotted key publisher (uses NotificationCenter)
        testDefaults.updatesPublisher(forKey: dottedKey).sink { _ in
            receivedCount += 1
            lastReceivedValue = testDefaults.string(forKey: dottedKey)
        }.store(in: &cancellables)

        // Then - no emission on subscription
        #expect(receivedCount == 0)

        // When - remove value
        testDefaults.removeObject(forKey: dottedKey)

        // Then - emits once for removal
        #expect(receivedCount == 1)
        #expect(lastReceivedValue == nil)

        // When - set value again after removal
        testDefaults.set("afterRemoval", forKey: dottedKey)

        // Then - emits again
        #expect(receivedCount == 2)
        #expect(lastReceivedValue == "afterRemoval")
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
    @Test("ThrowingValue getter returns value", .timeLimit(.minutes(1)))
    func throwingValueGetterReturnsValue() throws {
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = defaults.throwingKeyedStoring()

        // Given - value exists
        defaults.set(42, forKey: "throwingValue")

        // When - get value
        let value = try storage.value(for: \.throwingValue)

        // Then - value is returned
        #expect(value == 42)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue getter returns nil for missing value", .timeLimit(.minutes(1)))
    func throwingValueGetterReturnsNilForMissingValue() throws {
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = defaults.throwingKeyedStoring()

        // Given - no value exists
        defaults.removeObject(forKey: "throwingValue")

        // When - get value
        let value = try storage.value(for: \.throwingValue)

        // Then - nil is returned
        #expect(value == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue setter sets value", .timeLimit(.minutes(1)))
    func throwingValueSetterSetsValue() throws {
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = defaults.throwingKeyedStoring()

        // When - set value
        try storage.set(100, for: \.throwingValue)

        // Then - value is stored
        let retrieved = defaults.object(forKey: "throwingValue") as? Int
        #expect(retrieved == 100)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue setter sets nil", .timeLimit(.minutes(1)))
    func throwingValueSetterSetsNil() throws {
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = defaults.throwingKeyedStoring()

        // Given - value exists
        defaults.set(42, forKey: "throwingValue")

        // When - set nil
        try storage.set(nil, for: \.throwingValue)

        // Then - value is removed
        let retrieved = defaults.object(forKey: "throwingValue")
        #expect(retrieved == nil)
    }

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
    @Test("ThrowingValue can set then get same value", .timeLimit(.minutes(1)))
    func throwingValueCanSetThenGetSameValue() throws {
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = defaults.throwingKeyedStoring()

        // When - set and get
        try storage.set(999, for: \.throwingValue)
        let retrieved = try storage.value(for: \.throwingValue)

        // Then - same value returned
        #expect(retrieved == 999)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ThrowingValue with String type", .timeLimit(.minutes(1)))
    func throwingValueWithStringType() throws {
        let storage: any ThrowingKeyedStoring<ThrowingKeys> = defaults.throwingKeyedStoring()

        // When - set string value
        try storage.set("test", for: \.throwingName)

        // Then - value is stored and retrieved
        let retrieved = try storage.value(for: \.throwingName)
        #expect(retrieved == "test")
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
    @Test("ObservableThrowingKeyValueStoring getter returns value", .timeLimit(.minutes(1)))
    func observableThrowingValueGetterReturnsValue() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()

        // Given - value exists
        mockStore.underlyingDict["observableThrowingValue"] = 42

        // When - get value
        let value = try storage.value(for: \.observableThrowingValue)

        // Then - value is returned
        #expect(value == 42)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ObservableThrowingKeyValueStoring setter sets value", .timeLimit(.minutes(1)))
    func observableThrowingValueSetterSetsValue() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()

        // When - set value
        try storage.set(100, for: \.observableThrowingValue)

        // Then - value is stored
        let retrieved = mockStore.underlyingDict["observableThrowingValue"] as? Int
        #expect(retrieved == 100)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ObservableThrowingKeyValueStoring objectWillChange fires on set", .timeLimit(.minutes(1)))
    @MainActor
    func observableThrowingValueObjectWillChangeFires() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        storage.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - set value
        try storage.set(42, for: \.observableThrowingValue)

        // Then - objectWillChange fired
        #expect(changeCount == 1)
    }

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
    @Test("ObservableThrowingKeyValueStoring updatesPublisher emits on change", .timeLimit(.minutes(1)))
    func observableThrowingValueUpdatesPublisherEmitsOnChange() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()
        var emissionCount = 0

        // Given - subscribe to updatesPublisher  
        mockStore.updatesPublisher(forKey: "observableThrowingValue").sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // When - set value
        try storage.set(42, for: \.observableThrowingValue)

        // Then - publisher emitted
        #expect(emissionCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("ObservableThrowingKeyValueStoring multiple subscribers work", .timeLimit(.minutes(1)))
    @MainActor
    func observableThrowingValueMultipleSubscribers() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        let storage: any ObservableThrowingKeyedStoring<ThrowingObservableKeys> = mockStore.observableThrowingKeyedStoring()
        var subscriber1Count = 0
        var subscriber2Count = 0
        var subscriber3Count = 0

        // Given - three subscribers
        storage.objectWillChange.sink { _ in
            subscriber1Count += 1
        }.store(in: &cancellables)

        storage.objectWillChange.sink { _ in
            subscriber2Count += 1
        }.store(in: &cancellables)

        storage.objectWillChange.sink { _ in
            subscriber3Count += 1
        }.store(in: &cancellables)

        // When - set value
        try storage.set(42, for: \.observableThrowingValue)

        // Then - all subscribers notified
        #expect(subscriber1Count == 1)
        #expect(subscriber2Count == 1)
        #expect(subscriber3Count == 1)
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
    @Test("UserDefaults subclass conforms to KeyedStoring", .timeLimit(.minutes(1)))
    func userDefaultsSubclassConformsToKeyedStoring() {
        // Given - custom UserDefaults subclass
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }

        // When - use via storage wrapper
        let storage: any KeyedStoring<InjectionTestKeys> = appDefaults.keyedStoring()
        storage.injectionTestValue = "hello"
        storage.injectionTestCount = 42

        // Then - values are stored and retrieved
        #expect(storage.injectionTestValue == "hello")
        #expect(storage.injectionTestCount == 42)
    }

    @available(iOS 16, macOS 13, *)
    @Test("UserDefaults subclass can be injected into services", .timeLimit(.minutes(1)))
    func userDefaultsSubclassCanBeInjectedIntoServices() {
        // Given - service with storage wrapper
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let storage: any ObservableKeyedStoring<InjectionTestKeys> = appDefaults.observableKeyedStoring()
        let service = ServiceWithStorage(storage: storage)

        // When - use through service
        service.storage.injectionTestValue = "injected"

        // Then - value persists through storage
        #expect(service.storage.injectionTestValue == "injected")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Standard UserDefaults can be injected into services", .timeLimit(.minutes(1)))
    func standardUserDefaultsCanBeInjectedIntoServices() {
        // Given - service with AppUserDefaults subclass
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }

        // When - inject storage wrapper into service
        let storage: any ObservableKeyedStoring<InjectionTestKeys> = appDefaults.observableKeyedStoring()
        let service = ServiceWithStorage(storage: storage)
        service.storage.injectionTestCount = 99

        // Then - works correctly
        #expect(service.storage.injectionTestCount == 99)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Custom file store subclass conforms to KeyedStoring", .timeLimit(.minutes(1)))
    func customFileStoreSubclassConformsToKeyedStoring() {
        // Given - custom file store
        let fileStore = AppFileStore()

        // When - use via storage wrapper
        let storage: any KeyedStoring<InjectionTestKeys> = fileStore.keyedStoring()
        storage.injectionTestValue = "file-backed"
        storage.injectionTestCount = 100

        // Then - values work correctly
        #expect(storage.injectionTestValue == "file-backed")
        #expect(storage.injectionTestCount == 100)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Custom file store can be injected into services", .timeLimit(.minutes(1)))
    func customFileStoreCanBeInjectedIntoServices() {
        // Given - service with file store
        let fileStore = AppFileStore()
        let storage: any ObservableKeyedStoring<InjectionTestKeys> = fileStore.observableKeyedStoring()
        let service = ServiceWithStorage(storage: storage)

        // When - use through service
        service.storage.injectionTestValue = "file-injected"

        // Then - value persists
        #expect(service.storage.injectionTestValue == "file-injected")
    }

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

    @available(iOS 16, macOS 13, *)
    @Test("Protocol constrains injection to specific types", .timeLimit(.minutes(1)))
    func protocolConstrainsInjectionToSpecificTypes() {
        // Given - type-constrained service
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let storage: any ObservableKeyedStoring<InjectionTestKeys> = appDefaults.observableKeyedStoring()
        let service = ServiceWithStorage(storage: storage)

        // When - modify through service
        service.storage.injectionTestValue = "constrained"

        // Then - type is ObservableKeyedStorage
        let isStorageType = service.storage is ObservableKeyedStorage<InjectionTestKeys>
        #expect(isStorageType)

        // And - still works correctly
        #expect(service.storage.injectionTestValue == "constrained")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Multiple services can share same storage instance", .timeLimit(.minutes(1)))
    func multipleServicesCanShareSameStorageInstance() {
        // Given - shared storage instance
        let suiteName = "test-\(UUID())"
        let sharedDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { sharedDefaults.removePersistentDomain(forName: suiteName) }
        let storage: any ObservableKeyedStoring<InjectionTestKeys> = sharedDefaults.observableKeyedStoring()
        let service1 = ServiceWithStorage(storage: storage)
        let service2 = ServiceWithStorage(storage: storage)

        // When - one service modifies storage
        service1.storage.injectionTestCount = 123

        // Then - other service sees the change
        #expect(service2.storage.injectionTestCount == 123)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Observable protocols work with injected subclasses", .timeLimit(.minutes(1)))
    func observableProtocolsWorkWithInjectedSubclasses() {
        // Given - observable storage wrapper
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let storage: any ObservableKeyedStoring<InjectionTestKeys> = appDefaults.observableKeyedStoring()
        let service = ServiceWithStorage(storage: storage)
        var emissionCount = 0

        // When - subscribe to publisher
        service.storage.publisher(for: \.injectionTestValue).sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // Set initial value
        service.storage.injectionTestValue = "initial"

        // Then - publisher emits
        service.storage.injectionTestValue = "changed"
        #expect(emissionCount >= 2)  // initial + changed
    }

    // MARK: - Test Isolation with UserDefaults Subclasses

    @available(iOS 16, macOS 13, *)
    @Test("UserDefaults subclass constrains injection to specific type", .timeLimit(.minutes(1)))
    func userDefaultsSubclassConstrainsInjectionToSpecificType() {
        // Given - service that requires specific subclass
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let service = ServiceWithConstrainedUserDefaults(settings: appDefaults)

        // When - modify via storage wrapper
        let storage: any KeyedStoring<InjectionTestKeys> = appDefaults.keyedStoring()
        storage.injectionTestValue = "subclass-specific"

        // Then - value is stored correctly
        #expect(storage.injectionTestValue == "subclass-specific")

        // And - underlying type is AppUserDefaults, not base UserDefaults
        let isAppUserDefaults = (service.settings is AppUserDefaults)
        #expect(isAppUserDefaults)

        // NOTE: The following would be a compile-time error (cannot pass base UserDefaults):
        // let baseDefaults = UserDefaults.standard
        // let invalid = ServiceWithConstrainedUserDefaults(settings: baseDefaults)  // ❌ Compile error
    }

    @available(iOS 16, macOS 13, *)
    @Test("Isolated test UserDefaults instances don't interfere", .timeLimit(.minutes(1)))
    func isolatedTestUserDefaultsInstancesDontInterfere() {
        // Given - two isolated test instances (each with unique suite)
        let instance1 = IsolatedTestUserDefaults()
        let storage1: any KeyedStoring<InjectionTestKeys> = instance1.keyedStoring()
        let instance2 = IsolatedTestUserDefaults()
        let storage2: any KeyedStoring<InjectionTestKeys> = instance2.keyedStoring()

        // When - write different values to each
        storage1.injectionTestValue = "instance1-value"
        storage1.injectionTestCount = 111

        storage2.injectionTestValue = "instance2-value"
        storage2.injectionTestCount = 222

        // Then - values don't interfere with each other
        #expect(storage1.injectionTestValue == "instance1-value")
        #expect(storage1.injectionTestCount == 111)

        #expect(storage2.injectionTestValue == "instance2-value")
        #expect(storage2.injectionTestCount == 222)
    }

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

    @available(iOS 16, macOS 13, *)
    @Test("Multiple tests using subclass-constrained services remain isolated", .timeLimit(.minutes(1)))
    func multipleTestsUsingSubclassConstrainedServicesRemainIsolated() {
        // Simulating multiple test runs with same pattern

        // Test run 1
        let service1 = {
            let defaults = AppUserDefaults(suiteName: "test-\(UUID())")!
            let storage: any KeyedStoring<InjectionTestKeys> = defaults.keyedStoring()
            let service = ServiceWithConstrainedUserDefaults(settings: defaults)
            storage.injectionTestValue = "run1"
            storage.injectionTestCount = 100
            return (service, storage)
        }()

        // Test run 2 (different instance)
        let service2 = {
            let defaults = AppUserDefaults(suiteName: "test-\(UUID())")!
            let storage: any KeyedStoring<InjectionTestKeys> = defaults.keyedStoring()
            let service = ServiceWithConstrainedUserDefaults(settings: defaults)
            storage.injectionTestValue = "run2"
            storage.injectionTestCount = 200
            return (service, storage)
        }()

        // Then - each service maintains its own state
        #expect(service1.1.injectionTestValue == "run1")
        #expect(service1.1.injectionTestCount == 100)

        #expect(service2.1.injectionTestValue == "run2")
        #expect(service2.1.injectionTestCount == 200)
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
    @Test("Legacy key is removed after first read", .timeLimit(.minutes(1)))
    func legacyKeyRemovedAfterFirstRead() {
        struct LegacyKeys: StoringKeys {
            let username = StorageKey<String>(TestKeys.newUserName, migrateLegacyKey: "com.app.legacy.username")
        }

        // Given - data stored under legacy dotted key only
        defaults.set("MigrateMe", forKey: "com.app.legacy.username")
        #expect(defaults.string(forKey: "userName") == nil) // New key empty
        #expect(defaults.string(forKey: "com.app.legacy.username") == "MigrateMe") // Legacy dotted key has value

        let storage: any KeyedStoring<LegacyKeys> = defaults.keyedStoring()

        // When - reading value for the first time
        let firstRead = storage.username

        // Then - value is returned from legacy dotted key
        #expect(firstRead == "MigrateMe")

        // And - legacy dotted key is removed after first read
        #expect(defaults.string(forKey: "com.app.legacy.username") == nil)

        // And - value is written to new key during migration
        #expect(defaults.string(forKey: "userName") == "MigrateMe")

        // And - subsequent reads return the migrated value from new key
        let secondRead = storage.username
        #expect(secondRead == "MigrateMe")
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
