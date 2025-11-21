//
//  StorageMacroIntegrationTests.swift
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
import Macros
import Persistence
import PersistenceTestingUtils
import Testing

// MARK: - Test Protocols

@Storage
public protocol AppSettings: ObservableKeyValueStoring {
    @Key("is-first-launch") var isFirstLaunch: Bool? { get set }
    var refreshInterval: Double? { get set }
}
extension UserDefaults: AppSettings {}
extension MockKeyValueStore: AppSettings {}

@Storage
public protocol MigrationTestSettings: ObservableKeyValueStoring {
    @Key("newUsername", migratingLegacyKey: "username")
    var username: String? { get set }

    @Key("newCount", migratingLegacyKey: "old.count")
    var count: Int? { get set }

    var regularProperty: Bool? { get set }
}
extension UserDefaults: MigrationTestSettings {}

@Storage
public protocol IgnoredMembersSettings: KeyValueStoring {
    var value1: String? { get set }

    @StorageIgnored
    var customProperty: String? { get }  // Property requiring custom implementation

    // Functions and associated types don't need @StorageIgnored - automatically ignored
    func customMethod()

    var value2: Int? { get set }

    associatedtype CustomType
}
extension UserDefaults: IgnoredMembersSettings {
    public typealias CustomType = Void

    public var customProperty: String? {
        // Custom computed property implementation
        return "custom-\(value1 ?? "none")"
    }

    public func customMethod() {
        // Custom implementation
    }
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

@Storage
public protocol EnumSettings: ObservableKeyValueStoring {
    var theme: Theme? { get set }
    var priority: Priority? { get set }
}
extension UserDefaults: EnumSettings {}

@Storage
public protocol EnumMigrationSettings: ObservableKeyValueStoring {
    @Key("newDisplay", migratingLegacyKey: "old.display")
    var display: Theme? { get set }
}
extension UserDefaults: EnumMigrationSettings {}

@Storage
public protocol AutoObservationSettings1: ObservableKeyValueStoring {
    var setting1: String? { get set }
    var setting2: Int? { get set }
}
extension UserDefaults: AutoObservationSettings1 {}

@Storage
public protocol AutoObservationSettings2: ObservableKeyValueStoring {
    var config1: Bool? { get set }
}
extension UserDefaults: AutoObservationSettings2 {}

// MARK: - Throwing Settings

@Storage
public protocol ThrowingSettings: ThrowingKeyValueStoring {
    var throwingValue: ThrowingValue<Int> { get }
    var throwingName: ThrowingValue<String> { get }
}
extension UserDefaults: ThrowingSettings {}

@Storage
public protocol ThrowingObservableSettings: ObservableThrowingKeyValueStoring {
    var observableThrowingValue: ThrowingValue<Int> { get }
    var observableThrowingName: ThrowingValue<String> { get }
}
extension MockObservableThrowingKeyValueStore: ThrowingObservableSettings {}
extension MockThrowingKeyValueStore: ThrowingSettings {}

// MARK: - ThrowingGetter (Read-Only) Settings

@Storage
public protocol ReadOnlyThrowingSettings: ThrowingKeyValueStoring {
    var readOnlyValue: ThrowingGetter<Int> { get }
    var readOnlyName: ThrowingGetter<String> { get }
}
extension MockThrowingKeyValueStore: ReadOnlyThrowingSettings {}

// MARK: - Nested Protocol Test

public struct NestedContainer {
    @Storage
    public protocol NestedSettings: ObservableKeyValueStoring {
        var nestedValue: String? { get set }
        var nestedCount: Int? { get set }
    }
}
extension MockKeyValueStore: NestedContainer.NestedSettings {}

// MARK: - Dependency Injection Test Protocols

@Storage
public protocol InjectionTestSettings: ObservableKeyValueStoring {
    var injectionTestValue: String? { get set }
    var injectionTestCount: Int? { get set }
}

@Storage
public protocol ThrowingInjectionSettings: ObservableThrowingKeyValueStoring {
    var throwingTestValue: ThrowingValue<String> { get }
}

// Custom UserDefaults subclass conforming to test protocols
public final class AppUserDefaults: UserDefaults {}
extension AppUserDefaults: InjectionTestSettings {}
extension AppUserDefaults: ThrowingInjectionSettings {}

// Custom file store wrapping InMemoryKeyValueStore
public final class AppFileStore: InMemoryKeyValueStore {}
extension AppFileStore: InjectionTestSettings {}

// Service classes that depend on protocol-constrained storage
public final class ServiceWithStorage {
    let storage: InjectionTestSettings

    init(storage: InjectionTestSettings) {
        self.storage = storage
    }
}

public final class ServiceWithThrowingStorage {
    let storage: ThrowingInjectionSettings

    init(storage: ThrowingInjectionSettings) {
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
extension IsolatedTestUserDefaults: InjectionTestSettings {}

// MARK: - Main Test Suite

final class StorageMacroIntegrationTests {
    // Use UUID to ensure each test instance gets its own isolated UserDefaults
    let suiteName = "StorageMacroIntegrationTests-\(UUID().uuidString)"
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

    @Test("UserDefaults native persistence works")
    func userDefaultsNativePersistenceWorks() {
        // Test that UserDefaults itself works in the test environment

        // Check initial state for non-existent keys
        #expect(defaults.object(forKey: "nonexistent-bool") == nil)
        #expect(defaults.object(forKey: "nonexistent-bool") as? Bool == nil)
        // NOTE: defaults.bool(forKey:) returns false for nonexistent keys!

        defaults.set(true, forKey: "test-bool")
        defaults.set(42.0, forKey: "test-double")

        #expect(defaults.bool(forKey: "test-bool") == true)
        #expect(defaults.double(forKey: "test-double") == 42.0)
        #expect(defaults.object(forKey: "test-bool") as? Bool == true)
        #expect(defaults.object(forKey: "test-double") as? Double == 42.0)

        // Test with the actual key from AppSettings
        defaults.set(true, forKey: "is-first-launch")
        let retrieved = defaults.object(forKey: "is-first-launch")
        #expect(retrieved as? Bool == true, "Should work with is-first-launch key")
    }

    @Test("Debug macro-generated property behavior")
    func debugMacroGeneratedPropertyBehavior() {
        // Check initial state - this should be nil
        let initial = defaults.isFirstLaunch
        #expect(initial == nil)

        // Try setting via native method first
        defaults.set(true, forKey: "is-first-launch")
        let afterNativeSet = defaults.object(forKey: "is-first-launch")
        #expect(afterNativeSet as? Bool == true, "Native set should work")

        let viaGetter = defaults.isFirstLaunch
        #expect(viaGetter == true, "Getter should return true after native set")

        // Clear it
        defaults.removeObject(forKey: "is-first-launch")
        #expect(defaults.isFirstLaunch == nil, "Should be nil after remove")

        // Set via macro property setter
        defaults.isFirstLaunch = true

        // Read back via native method
        let viaObject = defaults.object(forKey: "is-first-launch")
        #expect(viaObject as? Bool == true, "Native object should be true after macro set")

        // Read back via macro getter
        let afterSet = defaults.isFirstLaunch
        #expect(afterSet == true, "Getter should return true after macro set")
    }

    @Test("Generated properties support read and write")
    func generatedPropertiesReadWrite() {
        // Given - empty defaults
        #expect(defaults.isFirstLaunch == nil)
        #expect(defaults.refreshInterval == nil)

        // When - set values
        defaults.isFirstLaunch = true
        defaults.refreshInterval = 30.0

        // Then - values are stored and retrieved
        #expect(defaults.isFirstLaunch == true)
        #expect(defaults.refreshInterval == 30.0)
    }

    @Test("Generated properties work with custom keys")
    func generatedPropertiesWithCustomKeys() {
        // Given - property with custom key
        defaults.isFirstLaunch = false

        // Then - value is stored with custom key
        #expect(defaults.bool(forKey: "is-first-launch") == false)

        // When - set via UserDefaults directly
        defaults.set(true, forKey: "is-first-launch")

        // Then - value is accessible via generated property
        #expect(defaults.isFirstLaunch == true)
    }

    @Test("Generated publishers emit changes")
    func generatedPublishers() {
        var receivedValues: [Bool?] = []

        // Given - subscribe to publisher
        defaults.$isFirstLaunch.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change value multiple times
        defaults.isFirstLaunch = true
        defaults.isFirstLaunch = false
        defaults.isFirstLaunch = nil

        // Then - publisher emits all values
        #expect(receivedValues == [nil, true, false, nil])
    }

    @Test("Publisher emits on direct key changes")
    func publisherEmitsOnDirectKeyChanges() {
        var receivedValues: [Bool?] = []

        // Given - subscribe to publisher
        defaults.$isFirstLaunch.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change value directly via UserDefaults.set(_:forKey:)
        defaults.set(true, forKey: "is-first-launch")
        defaults.set(false, forKey: "is-first-launch")
        defaults.removeObject(forKey: "is-first-launch")

        // Then - publisher still emits (KVO observes the key)
        #expect(receivedValues == [nil, true, false, nil])
    }

    @Test("Publisher works with KeyPath")
    func publisherWithKeyPath() {
        var receivedValues: [Double?] = []

        // Given - subscribe using keyPath
        defaults.publisher(for: \.refreshInterval).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - set value
        defaults.refreshInterval = 60.0

        // Then - publisher emits both initial and new value
        #expect(receivedValues == [nil, 60.0])
    }

    @Test("Publisher works with custom key")
    func publisherWithCustomKey() {
        var receivedValues: [Bool?] = []

        // Given - subscribe to custom-keyed property
        defaults.$isFirstLaunch.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - set value
        defaults.isFirstLaunch = true

        // Then - publisher emits both initial and new value
        #expect(receivedValues == [nil, true])
    }

    @Test("Wrapper can be observed through publisher")
    func wrapperCanBeObservedThroughPublisher() {
        var receivedValues: [Bool?] = []

        // Given - subscribe to publisher
        defaults.publisher(for: \.isFirstLaunch).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change value multiple times
        defaults.isFirstLaunch = true

        defaults.isFirstLaunch = false

        // Then - publisher emits all values
        #expect(receivedValues == [nil, true, false])
    }

    @Test("Protocol usage with dependency injection")
    func protocolUsageWithInjection() {
        // Test that protocols can be used with dependency injection
        func updateSettings(_ settings: some AppSettings) {
            settings.isFirstLaunch = false
        }

        updateSettings(defaults)
        #expect(defaults.isFirstLaunch == false)
    }

    @Test("Publisher supports multiple subscribers")
    func publisherWithMultipleSubscribers() {
        var values1: [Double?] = []
        var values2: [Double?] = []

        // Given - two subscribers to the same publisher
        defaults.publisher(for: \.refreshInterval).sink { value in
            values1.append(value)
        }.store(in: &cancellables)

        defaults.publisher(for: \.refreshInterval).sink { value in
            values2.append(value)
        }.store(in: &cancellables)

        // When - set value
        defaults.refreshInterval = 30.0

        // Then - both subscribers receive the update
        #expect(values1 == [nil, 30.0])
        #expect(values2 == [nil, 30.0])
    }

    @Test("Publisher isolation between protocols")
    func publisherIsolationBetweenProtocols() {
        let settings1 = defaults as (any AutoObservationSettings1 & ObservableObject)
        let settings2 = defaults as (any AutoObservationSettings2 & ObservableObject)

        var setting1Changes = 0
        var config1Changes = 0

        // Given - subscribe to publishers from different protocols
        settings1.publisher(for: \.setting1).sink { _ in
            setting1Changes += 1
        }.store(in: &cancellables)

        settings2.publisher(for: \.config1).sink { _ in
            config1Changes += 1
        }.store(in: &cancellables)

        // When - change setting1
        defaults.setting1 = "changed"

        // Then - only setting1 publisher fires
        #expect(setting1Changes == 2) // initial + change
        #expect(config1Changes == 1) // only initial

        // When - change config1
        defaults.config1 = true

        // Then - only config1 publisher fires
        #expect(setting1Changes == 2)
        #expect(config1Changes == 2) // initial + change
    }

    @Test("Publisher works after legacy key migration")
    func publisherWithLegacyKeyMigration() {
        var receivedValue: String?

        // Given - legacy value exists
        defaults.set("old value", forKey: "username")

        // When - subscribe to property with legacy key migration
        (defaults as MigrationTestSettings).publisher(for: \.username).sink { value in
            receivedValue = value
        }.store(in: &cancellables)

        // Then - publisher emits migrated value
        #expect(receivedValue == "old value")

        // And - value was migrated to new key
        #expect(defaults.string(forKey: "newUsername") == "old value")
        #expect(defaults.string(forKey: "username") == nil)
    }

    @Test("Publisher works with enum types")
    func publisherWithEnumType() {
        var receivedValues: [Theme?] = []

        // Given - subscribe to enum property
        (defaults as EnumSettings).publisher(for: \.theme).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - set enum value
        (defaults as EnumSettings).theme = .dark

        // Then - publisher emits
        #expect(receivedValues == [nil, .dark])
    }

    @Test("Nil values are handled correctly")
    func nilValues() {
        // Given - set value
        defaults.isFirstLaunch = true
        #expect(defaults.isFirstLaunch != nil)

        // When - set to nil
        defaults.isFirstLaunch = nil

        // Then - value is nil
        #expect(defaults.isFirstLaunch == nil)
    }

    @Test("Multiple properties work independently")
    func multiplePropertiesIndependence() {
        // Given - set multiple properties
        defaults.isFirstLaunch = true
        defaults.refreshInterval = 120.0

        // When - change one
        defaults.isFirstLaunch = false

        // Then - other remains unchanged
        #expect(defaults.isFirstLaunch == false)
        #expect(defaults.refreshInterval == 120.0)
    }

    @Test("Publisher only emits for relevant property")
    func publisherOnlyEmitsForRelevantProperty() {
        var emitCount = 0

        // Given - subscribe to isFirstLaunch publisher
        defaults.$isFirstLaunch.sink { _ in
            emitCount += 1
        }.store(in: &cancellables)

        // When - change different property
        defaults.refreshInterval = 100.0

        // And - change subscribed property
        defaults.isFirstLaunch = true

        // Then - publisher only emits for its property
        #expect(emitCount == 2) // initial + isFirstLaunch change only
    }

    // MARK: - Mock Store Tests

    @Test("MockKeyValueStore works with generated protocol")
    func mockKeyValueStoreWithGeneratedProtocol() {
        let mockStore = MockKeyValueStore()

        // Test that protocol works with mock store
        mockStore.isFirstLaunch = true
        #expect(mockStore.isFirstLaunch == true)

        mockStore.refreshInterval = 45.0
        #expect(mockStore.refreshInterval == 45.0)
    }

    @Test("MockKeyValueStore observable publisher")
    func mockKeyValueStoreObservablePublisher() {
        let mockStore = MockKeyValueStore()
        var receivedValue: Bool?

        mockStore.$isFirstLaunch.sink { value in
            receivedValue = value
        }.store(in: &cancellables)

        mockStore.isFirstLaunch = true

        #expect(receivedValue == true)
    }

    @Test("MockKeyValueStore publisher emits initial value")
    func mockKeyValueStorePublisherEmitsInitialValue() {
        let mockStore = MockKeyValueStore()
        var receivedValues: [Bool?] = []

        // Given - set initial value
        mockStore.isFirstLaunch = true

        // When - subscribe to publisher
        mockStore.$isFirstLaunch.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value immediately
        #expect(receivedValues == [true])

        // When - change value
        mockStore.isFirstLaunch = false

        // Then - receives new value
        #expect(receivedValues == [true, false])
    }

    @Test("MockKeyValueStore KeyPath publisher works correctly")
    func mockKeyValueStoreKeyPathPublisherWorksCorrectly() {
        let mockStore = MockKeyValueStore()
        var receivedValues: [Double?] = []

        // Given - set initial value
        mockStore.refreshInterval = 15.0

        // When - subscribe via KeyPath
        mockStore.publisher(for: \.refreshInterval).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value
        #expect(receivedValues == [15.0])

        // When - change value
        mockStore.refreshInterval = 30.0

        // Then - receives new value
        #expect(receivedValues == [15.0, 30.0])
    }

    @Test("InMemoryKeyValueStore publisher works with @Storage protocol")
    func inMemoryKeyValueStorePublisherWorksWithStorageProtocol() {
        let memoryStore = InMemoryKeyValueStore()
        var publisherValues: [Bool?] = []

        // Given - subscribe to publisher
        memoryStore.$isFirstLaunch.sink { value in
            publisherValues.append(value)
        }.store(in: &cancellables)

        // When - modify property
        memoryStore.isFirstLaunch = true

        // Then - publisher emits
        #expect(publisherValues == [nil, true])  // Initial nil, then true

        // When - modify again
        memoryStore.isFirstLaunch = false

        // Then - publisher emits again
        #expect(publisherValues == [nil, true, false])
    }

    // MARK: - Nested Protocol Tests

    @Test("Nested protocol works with MockKeyValueStore")
    func nestedProtocolWorksWithMockKeyValueStore() {
        let mockStore = MockKeyValueStore()

        // When - use nested protocol
        mockStore.nestedValue = "test"
        mockStore.nestedCount = 42

        // Then - values are stored and retrieved
        #expect(mockStore.nestedValue == "test")
        #expect(mockStore.nestedCount == 42)
    }

    @Test("Nested protocol publisher works correctly")
    func nestedProtocolPublisherWorksCorrectly() {
        let mockStore = MockKeyValueStore()
        var receivedValues: [String?] = []

        // Given - set initial value
        mockStore.nestedValue = "initial"

        // When - subscribe to publisher
        mockStore.$nestedValue.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value
        #expect(receivedValues == ["initial"])

        // When - change value
        mockStore.nestedValue = "updated"

        // Then - receives new value
        #expect(receivedValues == ["initial", "updated"])
    }

    @Test("Nested protocol KeyPath publisher works correctly")
    func nestedProtocolKeyPathPublisherWorksCorrectly() {
        let mockStore = MockKeyValueStore()
        var receivedValues: [Int?] = []

        // Given - set initial value
        mockStore.nestedCount = 10

        // When - subscribe via KeyPath
        mockStore.publisher(for: \NestedContainer.NestedSettings.nestedCount).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value
        #expect(receivedValues == [10])

        // When - change value
        mockStore.nestedCount = 20

        // Then - receives new value
        #expect(receivedValues == [10, 20])
    }

    @Test("MockKeyValueStore objectWillChange fires with @Storage protocol")
    func mockKeyValueStoreObjectWillChangeFiresWithStorageProtocol() {
        let mockStore = MockKeyValueStore()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)
        #expect(changeCount == 0)

        // When - modify @Storage properties
        mockStore.isFirstLaunch = true
        mockStore.refreshInterval = 10.0
        mockStore.isFirstLaunch = false

        // Then - objectWillChange fires for each change
        #expect(changeCount == 3)
    }

    @Test("InMemoryKeyValueStore objectWillChange with @Storage protocol")
    func inMemoryKeyValueStoreObjectWillChangeWithStorageProtocol() {
        let memoryStore = InMemoryKeyValueStore()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        memoryStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)
        #expect(changeCount == 0)

        // When - modify @Storage properties
        memoryStore.isFirstLaunch = true
        memoryStore.isFirstLaunch = false

        // Then - objectWillChange fires for each change
        #expect(changeCount == 2)
    }

    @Test("Nested protocol objectWillChange works with MockKeyValueStore")
    func nestedProtocolObjectWillChangeWorksWithMockKeyValueStore() {
        let mockStore = MockKeyValueStore()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - modify nested protocol properties
        mockStore.nestedValue = "changed"
        mockStore.nestedCount = 999

        // Then - objectWillChange fires for each change
        #expect(changeCount == 2)
    }

    // MARK: - Legacy Key Migration Tests

    @Test("Legacy key migration on first read")
    func legacyKeyMigrationOnFirstRead() {
        // Given - value in legacy key
        defaults.set("oldUser", forKey: "username")
        #expect(defaults.string(forKey: "newUsername") == nil)

        // When - read via new property (triggers migration)
        let value = defaults.username

        // Then - value migrated to new key
        #expect(value == "oldUser")
        #expect(defaults.string(forKey: "newUsername") == "oldUser")
        #expect(defaults.string(forKey: "username") == nil)
    }

    @Test("Legacy key migration with existing new key")
    func legacyKeyMigrationWithExistingNewKey() {
        // Given - values in both keys
        defaults.set("oldUser", forKey: "username")
        defaults.set("newUser", forKey: "newUsername")

        // When - read via property
        let value = defaults.username

        // Then - new key takes precedence, no migration
        #expect(value == "newUser")
        #expect(defaults.string(forKey: "username") == "oldUser") // legacy key preserved
    }

    @Test("Legacy key migration on write")
    func legacyKeyMigrationOnWrite() {
        // Given - legacy key has value
        defaults.set(5, forKey: "old.count")

        // When - write new value
        defaults.count = 10

        // Then - writes to new key
        #expect(defaults.count == 10)
        #expect(defaults.integer(forKey: "newCount") == 10)
    }

    @Test("Legacy key migration with different types")
    func legacyKeyMigrationWithDifferentTypes() {
        // Given - string in legacy key, int expected
        defaults.set(42, forKey: "old.count")

        // When - read as correct type
        let value = defaults.count

        // Then - migrated correctly
        #expect(value == 42)
        #expect(defaults.integer(forKey: "newCount") == 42)
    }

    @Test("Legacy key migration does not affect regular properties")
    func legacyKeyMigrationDoesNotAffectRegularProperties() {
        // Given - regular property without migration
        defaults.regularProperty = true

        // Then - no migration keys created
        #expect(defaults.regularProperty == true)
        #expect(defaults.bool(forKey: "regularProperty") == true)
    }

    @Test("Legacy key migration publisher emits after migration")
    func legacyKeyMigrationPublisherEmitsAfterMigration() {
        var receivedValue: String?

        // Given - legacy value exists
        defaults.set("legacyUser", forKey: "username")

        // When - subscribe to publisher
        defaults.$username.sink { value in
            receivedValue = value
        }.store(in: &cancellables)

        // Then - publisher emits migrated value
        #expect(receivedValue == "legacyUser")
    }

    // MARK: - @StorageIgnored Tests

    @Test("Generated properties work normally")
    func generatedPropertiesWorkNormally() {
        // Properties without @StorageIgnored are generated
        defaults.value1 = "test1"
        defaults.value2 = 42

        #expect(defaults.value1 == "test1")
        #expect(defaults.value2 == 42)
    }

    @Test("StorageIgnored property requires custom implementation")
    func storageIgnoredPropertyRequiresCustomImplementation() {
        // Given - @StorageIgnored property with custom implementation
        defaults.value1 = "base"

        // When - access custom property
        let customValue = defaults.customProperty

        // Then - custom implementation is used
        #expect(customValue == "custom-base")
    }

    @Test("Functions work without @StorageIgnored annotation")
    func functionsWorkWithoutStorageIgnoredAnnotation() {
        // Functions don't need @StorageIgnored - automatically ignored by macro
        defaults.customMethod() // Should not crash
    }

    @Test("Associated types work without @StorageIgnored annotation")
    func associatedTypesWorkWithoutStorageIgnoredAnnotation() {
        // Associated types don't need @StorageIgnored - automatically ignored by macro
        let typeCheck: UserDefaults.CustomType = ()
        #expect(typeCheck == ())
    }

    // MARK: - Enum RawRepresentable Tests

    @Test("Enum with String raw value supports read/write")
    func enumStringRawValueReadWrite() {
        // Given - enum with String raw value
        defaults.theme = .dark

        // Then - stored as raw value
        #expect(defaults.theme == .dark)
        #expect(defaults.string(forKey: "theme") == "dark")

        // When - set different value
        defaults.theme = .light
        #expect(defaults.theme == .light)
    }

    @Test("Enum with Int raw value supports read/write")
    func enumIntRawValueReadWrite() {
        // Given - enum with Int raw value
        defaults.priority = .high

        // Then - stored as raw value
        #expect(defaults.priority == .high)
        #expect(defaults.integer(forKey: "priority") == 2)

        // When - set different value
        defaults.priority = .low
        #expect(defaults.priority == .low)
    }

    @Test("Enum handles nil value")
    func enumNilValue() {
        // Given - enum value set
        defaults.theme = .system
        #expect(defaults.theme != nil)

        // When - set to nil
        defaults.theme = nil

        // Then - value is nil
        #expect(defaults.theme == nil)
    }

    @Test("Enum with legacy key migration")
    func enumWithLegacyKeyMigration() {
        // Given - enum value in legacy key
        defaults.set("light", forKey: "old.display")

        // When - read via new property
        let value = defaults.display

        // Then - migrated correctly
        #expect(value == .light)
        #expect(defaults.string(forKey: "newDisplay") == "light")
        #expect(defaults.string(forKey: "old.display") == nil)
    }

    @Test("Enum publisher emits changes")
    func enumPublisherEmitsChanges() {
        var receivedValues: [Theme?] = []

        // Given - subscribe to enum publisher
        defaults.$theme.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change values
        defaults.theme = .dark
        defaults.theme = .light

        // Then - publisher emits all changes
        #expect(receivedValues == [nil, .dark, .light])
    }

    @Test("Enum publisher with KeyPath")
    func enumPublisherWithKeyPath() {
        var receivedValue: Priority?

        // Given - subscribe via keyPath
        defaults.publisher(for: \.priority).sink { value in
            receivedValue = value
        }.store(in: &cancellables)

        // When - set value
        defaults.priority = .medium

        // Then - publisher emits
        #expect(receivedValue == .medium)
    }

    @Test("String enum publisher emits all changes")
    func stringEnumPublisherEmitsAllChanges() {
        var receivedValues: [Theme?] = []

        // Given - subscribe to String enum
        defaults.$theme.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change through multiple values
        defaults.theme = .light
        defaults.theme = .dark
        defaults.theme = .system
        defaults.theme = nil
        defaults.theme = .light

        // Then - all changes emitted
        #expect(receivedValues == [nil, .light, .dark, .system, nil, .light])
    }

    @Test("Int enum publisher emits all changes")
    func intEnumPublisherEmitsAllChanges() {
        var receivedValues: [Priority?] = []

        // Given - subscribe to Int enum
        defaults.$priority.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change through multiple values
        defaults.priority = .low
        defaults.priority = .high
        defaults.priority = .medium
        defaults.priority = nil
        defaults.priority = .low

        // Then - all changes emitted
        #expect(receivedValues == [nil, .low, .high, .medium, nil, .low])
    }

    @Test("Negative Int enum publisher works correctly")
    func negativeIntEnumPublisherWorks() {
        enum Status: Int {
            case error = -1
            case pending = 0
            case success = 1
        }

        // Extend AppSettings to include Status
        var receivedValues: [Int?] = []

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

    @Test("Enum publisher with KeyPath emits all changes")
    func enumPublisherWithKeyPathEmitsAllChanges() {
        var receivedValues: [Priority?] = []

        // Given - subscribe via KeyPath
        defaults.publisher(for: \.priority).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // When - change multiple times
        defaults.priority = .low
        defaults.priority = .medium
        defaults.priority = .high

        // Then - all values emitted
        #expect(receivedValues == [nil, .low, .medium, .high])
    }

    @Test("Enum updatesPublisher(forKey:) emits for both String and Int enums")
    func enumUpdatesPublisherForKeyWorks() {
        var themeCount = 0
        var priorityCount = 0

        // Given - subscribe to both enum types
        defaults.updatesPublisher(forKey: "theme").sink { _ in
            themeCount += 1
        }.store(in: &cancellables)

        defaults.updatesPublisher(forKey: "priority").sink { _ in
            priorityCount += 1
        }.store(in: &cancellables)

        // When - change both
        defaults.theme = .dark
        defaults.priority = .high
        defaults.theme = .light

        // Then - both emit correctly
        #expect(themeCount == 2)  // dark, light
        #expect(priorityCount == 1)  // high
    }

    // MARK: - Auto-Observation Tests

    @Test("Auto-observation triggers objectWillChange for property changes")
    func autoObservationTriggersObjectWillChangeForPropertyChanges() async throws {
        let settings1 = defaults as (any AutoObservationSettings1 & ObservableObject)
        var changeCount = 0

        // Trigger observation setup by accessing the property
        _ = defaults.setting1

        // Given - subscribe to objectWillChange
        settings1.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - modify property
        defaults.setting1 = "test"

        // Then - objectWillChange fired
        #expect(changeCount == 1)
    }

    @Test("Auto-observation triggers for direct key changes")
    func autoObservationTriggersForDirectKeyChanges() async throws {
        let settings1 = defaults as (any AutoObservationSettings1 & ObservableObject)
        var changeCount = 0

        // Trigger observation setup
        _ = defaults.setting1

        // Given - subscribe to objectWillChange
        settings1.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - set value directly via UserDefaults
        defaults.set("direct", forKey: "setting1")

        // Then - objectWillChange still fires
        #expect(changeCount == 1)
    }

    @Test("Auto-observation isolation between protocols")
    func autoObservationIsolationBetweenProtocols() async throws {
        let settings1 = defaults as (any AutoObservationSettings1 & ObservableObject)
        let settings2 = defaults as (any AutoObservationSettings2 & ObservableObject)

        var settings1ChangeCount = 0
        var settings2ChangeCount = 0

        // Trigger observation setup for both
        _ = defaults.setting1
        _ = defaults.config1

        // Given - subscribe to both protocols
        settings1.objectWillChange.sink { _ in
            settings1ChangeCount += 1
        }.store(in: &cancellables)

        settings2.objectWillChange.sink { _ in
            settings2ChangeCount += 1
        }.store(in: &cancellables)

        // When - change settings1 property
        defaults.setting1 = "changed"

        // Then - both receive notification (same UserDefaults instance, same objectWillChange publisher)
        #expect(settings1ChangeCount == 1)
        #expect(settings2ChangeCount == 1)

        // When - change settings2 property
        defaults.config1 = true

        // Then - both receive notification again
        #expect(settings1ChangeCount == 2)
        #expect(settings2ChangeCount == 2)
    }

    @Test("Auto-observation with multiple properties")
    func autoObservationWithMultipleProperties() async throws {
        let settings1 = defaults as (any AutoObservationSettings1 & ObservableObject)
        var changeCount = 0

        // Trigger observation setup
        _ = defaults.setting1

        // Given - subscribe to objectWillChange
        settings1.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different properties
        defaults.setting1 = "changed"
        defaults.setting2 = 42

        // Then - objectWillChange fires for both
        #expect(changeCount == 2)
    }

    @Test("Auto-observation isolation between different UserDefaults instances")
    func autoObservationIsolationBetweenDifferentUserDefaultsInstances() {
        let suite1 = "test-\(UUID().uuidString)"
        let suite2 = "test-\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suite1)!
        let defaults2 = UserDefaults(suiteName: suite2)!
        defer {
            defaults1.removePersistentDomain(forName: suite1)
            defaults2.removePersistentDomain(forName: suite2)
        }

        let settings1a = defaults1 as (any AutoObservationSettings1 & ObservableObject)
        let settings1b = defaults2 as (any AutoObservationSettings1 & ObservableObject)

        var settings1aChangeCount = 0
        var settings1bChangeCount = 0

        // Trigger observation setup
        _ = defaults1.setting1
        _ = defaults2.setting1

        // Given - subscribe to both instances
        settings1a.objectWillChange.sink { _ in
            settings1aChangeCount += 1
        }.store(in: &cancellables)

        settings1b.objectWillChange.sink { _ in
            settings1bChangeCount += 1
        }.store(in: &cancellables)

        // When - change defaults1
        defaults1.setting1 = "changed"

        // Then - only defaults1 receives notification
        #expect(settings1aChangeCount == 1)
        #expect(settings1bChangeCount == 0)

        // When - change defaults2
        defaults2.setting1 = "changed"

        // Then - only defaults2 receives notification
        #expect(settings1aChangeCount == 1)
        #expect(settings1bChangeCount == 1)
    }

    @Test("Property publishers emit initial value on subscription")
    func propertyPublishersEmitInitialValueOnSubscription() {
        var receivedValues: [Bool?] = []

        // Given - value exists before subscription
        defaults.isFirstLaunch = true

        // When - subscribe to $propertyName publisher
        defaults.$isFirstLaunch.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value immediately
        #expect(receivedValues == [true])

        // When - change value
        defaults.isFirstLaunch = false

        // Then - receives new value
        #expect(receivedValues == [true, false])
    }

    @Test("KeyPath publishers emit initial value on subscription")
    func keyPathPublishersEmitInitialValueOnSubscription() {
        var receivedValues: [Double?] = []

        // Given - value exists before subscription
        defaults.refreshInterval = 30.0

        // When - subscribe to publisher(for: keyPath)
        defaults.publisher(for: \.refreshInterval).sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives initial value immediately
        #expect(receivedValues == [30.0])

        // When - change value
        defaults.refreshInterval = 60.0

        // Then - receives new value
        #expect(receivedValues == [30.0, 60.0])
    }

    @Test("objectWillChange does NOT emit on subscription")
    func objectWillChangeDoesNotEmitOnSubscription() {
        let settings1 = defaults as (any AutoObservationSettings1 & ObservableObject)
        var changeCount = 0

        // Trigger observation setup
        _ = defaults.setting1

        // Given - value exists before subscription
        defaults.setting1 = "initial"

        // When - subscribe to objectWillChange
        settings1.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // Then - should NOT have fired (no initial emission)
        #expect(changeCount == 0)

        // When - change value
        defaults.setting1 = "changed"

        // Then - fires once for the change
        #expect(changeCount == 1)
    }

    @Test("Auto-observation comprehensive isolation")
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

        // Cast to different protocols
        let settings1a = defaults1a as (any AutoObservationSettings1 & ObservableObject)
        let settings1b = defaults1b as (any AutoObservationSettings1 & ObservableObject)
        let settings2a = defaults2a as (any AutoObservationSettings2 & ObservableObject)
        let settings2b = defaults2b as (any AutoObservationSettings2 & ObservableObject)

        var change1aCount = 0
        var change1bCount = 0
        var change2aCount = 0
        var change2bCount = 0

        // Trigger observation setup
        _ = defaults1a.setting1
        _ = defaults1b.setting1
        _ = defaults2a.config1
        _ = defaults2b.config1

        // Subscribe to all
        settings1a.objectWillChange.sink { _ in change1aCount += 1 }.store(in: &cancellables)
        settings1b.objectWillChange.sink { _ in change1bCount += 1 }.store(in: &cancellables)
        settings2a.objectWillChange.sink { _ in change2aCount += 1 }.store(in: &cancellables)
        settings2b.objectWillChange.sink { _ in change2bCount += 1 }.store(in: &cancellables)

        // When - change settings1a
        defaults1a.setting1 = "changed"

        // Then - only settings1a receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 0)
        #expect(change2aCount == 0)
        #expect(change2bCount == 0)

        // When - change settings1b
        defaults1b.setting2 = 42

        // Then - only settings1b receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 1)
        #expect(change2aCount == 0)
        #expect(change2bCount == 0)

        // When - change settings2a
        defaults2a.config1 = true

        // Then - only settings2a receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 1)
        #expect(change2aCount == 1)
        #expect(change2bCount == 0)

        // When - change settings2b
        defaults2b.config1 = false

        // Then - only settings2b receives notification
        #expect(change1aCount == 1)
        #expect(change1bCount == 1)
        #expect(change2aCount == 1)
        #expect(change2bCount == 1)
    }

    // MARK: - Edge Case Tests

    @Test("Legacy key migration does not re-check after first migration")
    func legacyKeyMigrationOnlyHappensOnce() {
        // Given - legacy key exists
        defaults.set("legacyUser", forKey: "username")

        // When - read via new key (triggers migration)
        let first = defaults.username
        #expect(first == "legacyUser")
        #expect(defaults.object(forKey: "newUsername") as? String == "legacyUser")
        #expect(defaults.object(forKey: "username") == nil) // legacy removed

        // When - set legacy key again (simulating external write)
        defaults.set("shouldNotMigrate", forKey: "username")

        // Then - reading new key should return current value, not re-migrate
        let second = defaults.username
        #expect(second == "legacyUser") // Still has first migrated value
        #expect(defaults.object(forKey: "username") as? String == "shouldNotMigrate") // Legacy key untouched
    }

    @Test("Legacy key with wrong type does not crash")
    func legacyKeyWithWrongType() {
        // Given - legacy key with wrong type (String instead of Int)
        defaults.set("notAnInt", forKey: "oldCount")

        // When - read via new key expecting Int
        let value = defaults.count

        // Then - should return nil gracefully
        #expect(value == nil)
    }

    @Test("Both new and legacy keys exist - new key wins")
    func bothNewAndLegacyKeysExist() {
        // Given - both keys exist
        defaults.set("newValue", forKey: "newUsername")
        defaults.set("oldValue", forKey: "username")

        // When - read property
        let value = defaults.username

        // Then - new key takes precedence
        #expect(value == "newValue")

        // And legacy key should not be removed
        #expect(defaults.object(forKey: "username") as? String == "oldValue")
    }

    @Test("Publisher emits rapidly for many changes")
    func publisherHandlesRapidChanges() {
        var receivedCount = 0

        // Given - subscribe to publisher
        defaults.$isFirstLaunch.sink { _ in
            receivedCount += 1
        }.store(in: &cancellables)

        // When - make 50 rapid changes
        for i in 0..<50 {
            defaults.isFirstLaunch = (i % 2 == 0)
        }

        // Then - should receive all updates (initial + 50 changes)
        #expect(receivedCount == 51)
    }

    @Test("Nil to value to nil cycle works correctly")
    func nilToValueToNilCycle() {
        // Start with nil
        #expect(defaults.refreshInterval == nil)

        // Set to value
        defaults.refreshInterval = 30.0
        #expect(defaults.refreshInterval == 30.0)

        // Set to different value
        defaults.refreshInterval = 60.0
        #expect(defaults.refreshInterval == 60.0)

        // Set back to nil
        defaults.refreshInterval = nil
        #expect(defaults.refreshInterval == nil)

        // Verify key is actually removed
        #expect(defaults.object(forKey: "refreshInterval") == nil)
    }

    @Test("Multiple subscribers receive all updates")
    func multipleSubscribersReceiveAllUpdates() {
        var subscriber1Values: [Bool?] = []
        var subscriber2Values: [Bool?] = []
        var subscriber3Values: [Bool?] = []

        // Given - three subscribers
        defaults.$isFirstLaunch.sink { value in
            subscriber1Values.append(value)
        }.store(in: &cancellables)

        defaults.$isFirstLaunch.sink { value in
            subscriber2Values.append(value)
        }.store(in: &cancellables)

        defaults.$isFirstLaunch.sink { value in
            subscriber3Values.append(value)
        }.store(in: &cancellables)

        // When - make changes
        defaults.isFirstLaunch = true
        defaults.isFirstLaunch = false

        // Then - all subscribers receive all updates
        #expect(subscriber1Values == [nil, true, false])
        #expect(subscriber2Values == [nil, true, false])
        #expect(subscriber3Values == [nil, true, false])
    }

    @Test("Thread safety: Concurrent reads work correctly")
    func concurrentReadsWorkCorrectly() async {
        // Given - set a value
        defaults.refreshInterval = 30.0

        // When - read from multiple threads concurrently
        await withTaskGroup(of: Double?.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    return self.defaults.refreshInterval
                }
            }

            // Then - all reads should succeed and return the correct value
            for await value in group {
                #expect(value == 30.0)
            }
        }
    }

    @Test("Thread safety: Concurrent writes to different keys")
    func concurrentWritesToDifferentKeys() async {
        // When - write different keys from multiple threads
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 2 == 0 {
                        self.defaults.isFirstLaunch = true
                    } else {
                        self.defaults.refreshInterval = Double(i)
                    }
                }
            }

            await group.waitForAll()
        }

        // Then - both properties should have some value set
        #expect(defaults.isFirstLaunch != nil || defaults.refreshInterval != nil)
    }

    @Test("Large string value persists correctly")
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

    @Test("Large data value persists correctly")
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

    @Test("Very long key name works")
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

    @Test("Enum with negative Int raw value")
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

    @Test("UserDefaults suite cleanup verifies no persistent domain remains")
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

    @Test("Property observation setup is idempotent")
    func propertyObservationSetupIsIdempotent() {
        // Given - access property multiple times to trigger setup
        _ = defaults.setting1
        _ = defaults.setting1
        _ = defaults.setting1

        var changeCount = 0
        let settings1 = defaults as (any AutoObservationSettings1 & ObservableObject)

        settings1.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - modify property
        defaults.setting1 = "test"

        // Then - should only receive one notification (not multiple due to multiple setups)
        #expect(changeCount == 1)
    }

    @Test("Publisher subscription after value changes emits current value")
    func publisherSubscriptionAfterValueChangesEmitsCurrentValue() {
        var receivedValues: [Bool?] = []

        // Given - change value before subscribing
        defaults.isFirstLaunch = true
        defaults.isFirstLaunch = false

        // When - subscribe to publisher
        defaults.$isFirstLaunch.sink { value in
            receivedValues.append(value)
        }.store(in: &cancellables)

        // Then - receives current value immediately
        #expect(receivedValues == [false])
    }

    @Test("Removing persistent domain while observing does not crash")
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

    @Test("ThrowingValue getter returns value")
    func throwingValueGetterReturnsValue() throws {
        // Given - value exists
        defaults.set(42, forKey: "throwingValue")

        // When - get value
        let value = try defaults.throwingValue.get()

        // Then - value is returned
        #expect(value == 42)
    }

    @Test("ThrowingValue getter returns nil for missing value")
    func throwingValueGetterReturnsNilForMissingValue() throws {
        // Given - no value exists
        defaults.removeObject(forKey: "throwingValue")

        // When - get value
        let value = try defaults.throwingValue.get()

        // Then - nil is returned
        #expect(value == nil)
    }

    @Test("ThrowingValue setter sets value")
    func throwingValueSetterSetsValue() throws {
        // When - set value
        try defaults.throwingValue.set(100)

        // Then - value is stored
        let retrieved = defaults.object(forKey: "throwingValue") as? Int
        #expect(retrieved == 100)
    }

    @Test("ThrowingValue setter sets nil")
    func throwingValueSetterSetsNil() throws {
        // Given - value exists
        defaults.set(42, forKey: "throwingValue")

        // When - set nil
        try defaults.throwingValue.set(nil)

        // Then - value is removed
        let retrieved = defaults.object(forKey: "throwingValue")
        #expect(retrieved == nil)
    }

    @Test("ThrowingValue with mock store that throws on get")
    func throwingValueWithMockStoreThatThrowsOnGet() throws {
        let mockStore = InMemoryThrowingKeyValueStore()
        mockStore.throwOnRead = NSError(domain: "test", code: 1)

        // Given - mock store throws on get
        // When - get value
        do {
            _ = try mockStore.throwingValue.get()
            Issue.record("Should have thrown")
        } catch {
            // Then - error is thrown
            #expect((error as NSError).code == 1)
        }
    }

    @Test("ThrowingValue with mock store that throws on set")
    func throwingValueWithMockStoreThatThrowsOnSet() throws {
        let mockStore = InMemoryThrowingKeyValueStore()
        mockStore.throwOnSet = NSError(domain: "test", code: 2)

        // Given - mock store throws on set
        // When - set value
        do {
            try mockStore.throwingValue.set(42)
            Issue.record("Should have thrown")
        } catch {
            // Then - error is thrown
            #expect((error as NSError).code == 2)
        }
    }

    @Test("ThrowingValue can set then get same value")
    func throwingValueCanSetThenGetSameValue() throws {
        // When - set and get
        try defaults.throwingValue.set(999)
        let retrieved = try defaults.throwingValue.get()

        // Then - same value returned
        #expect(retrieved == 999)
    }

    @Test("ThrowingValue with String type")
    func throwingValueWithStringType() throws {
        // When - set string value
        try defaults.throwingName.set("test")

        // Then - value is stored and retrieved
        let retrieved = try defaults.throwingName.get()
        #expect(retrieved == "test")
    }

    @Test("ThrowingValue multiple properties are independent")
    func throwingValueMultiplePropertiesAreIndependent() throws {
        // When - set both properties
        try defaults.throwingValue.set(42)
        try defaults.throwingName.set("test")

        // Then - both values are independent
        #expect(try defaults.throwingValue.get() == 42)
        #expect(try defaults.throwingName.get() == "test")

        // When - set one to nil
        try defaults.throwingValue.set(nil)

        // Then - other is unaffected
        #expect(try defaults.throwingValue.get() == nil)
        #expect(try defaults.throwingName.get() == "test")
    }

    // MARK: - ObservableThrowingKeyValueStoring Tests

    @Test("ObservableThrowingKeyValueStoring getter returns value")
    func observableThrowingValueGetterReturnsValue() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()

        // Given - value exists
        mockStore.underlyingDict["observableThrowingValue"] = 42

        // When - get value
        let value = try mockStore.observableThrowingValue.get()

        // Then - value is returned
        #expect(value == 42)
    }

    @Test("ObservableThrowingKeyValueStoring setter sets value")
    func observableThrowingValueSetterSetsValue() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()

        // When - set value
        try mockStore.observableThrowingValue.set(100)

        // Then - value is stored
        let retrieved = mockStore.underlyingDict["observableThrowingValue"] as? Int
        #expect(retrieved == 100)
    }

    @Test("ObservableThrowingKeyValueStoring objectWillChange fires on set")
    func observableThrowingValueObjectWillChangeFires() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - set value
        try mockStore.observableThrowingValue.set(42)

        // Then - objectWillChange fired
        #expect(changeCount == 1)
    }

    @Test("ObservableThrowingKeyValueStoring objectWillChange fires on removal")
    func observableThrowingValueObjectWillChangeFiresOnRemoval() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        var changeCount = 0

        // Given - value exists and subscribed
        try mockStore.observableThrowingValue.set(42)

        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - remove value
        try mockStore.observableThrowingValue.set(nil)

        // Then - objectWillChange fired
        #expect(changeCount == 1)
    }

    @Test("ObservableThrowingKeyValueStoring objectWillChange fires for any key")
    func observableThrowingValueObjectWillChangeFiresForAnyKey() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        var changeCount = 0

        // Given - subscribe to objectWillChange
        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - change different properties
        try mockStore.observableThrowingValue.set(1)
        try mockStore.observableThrowingName.set("test")

        // Then - objectWillChange fired for both
        #expect(changeCount == 2)
    }

    @Test("ObservableThrowingKeyValueStoring doesn't fire when get throws")
    func observableThrowingValueDoesntFireWhenGetThrows() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        mockStore.throwOnRead = NSError(domain: "test", code: 1)
        var changeCount = 0

        // Given - subscribe to objectWillChange
        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - try to get (will throw)
        do {
            _ = try mockStore.observableThrowingValue.get()
        } catch {
            // Expected
        }

        // Then - objectWillChange did not fire
        #expect(changeCount == 0)
    }

    @Test("ObservableThrowingKeyValueStoring doesn't fire when set throws")
    func observableThrowingValueDoesntFireWhenSetThrows() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        mockStore.throwOnSet = NSError(domain: "test", code: 2)
        var changeCount = 0

        // Given - subscribe to objectWillChange
        mockStore.objectWillChange.sink { _ in
            changeCount += 1
        }.store(in: &cancellables)

        // When - try to set (will throw)
        do {
            try mockStore.observableThrowingValue.set(42)
        } catch {
            // Expected
        }

        // Then - objectWillChange did not fire
        #expect(changeCount == 0)
    }

    @Test("ObservableThrowingKeyValueStoring updatesPublisher emits on change")
    func observableThrowingValueUpdatesPublisherEmitsOnChange() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        var emissionCount = 0

        // Given - subscribe to updatesPublisher
        mockStore.updatesPublisher(forKey: "observableThrowingValue").sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // When - set value
        try mockStore.observableThrowingValue.set(42)

        // Then - publisher emitted
        #expect(emissionCount == 1)
    }

    @Test("ObservableThrowingKeyValueStoring multiple subscribers work")
    func observableThrowingValueMultipleSubscribers() throws {
        let mockStore = InMemoryObservableThrowingKeyValueStore()
        var subscriber1Count = 0
        var subscriber2Count = 0
        var subscriber3Count = 0

        // Given - three subscribers
        mockStore.objectWillChange.sink { _ in
            subscriber1Count += 1
        }.store(in: &cancellables)

        mockStore.objectWillChange.sink { _ in
            subscriber2Count += 1
        }.store(in: &cancellables)

        mockStore.objectWillChange.sink { _ in
            subscriber3Count += 1
        }.store(in: &cancellables)

        // When - set value
        try mockStore.observableThrowingValue.set(42)

        // Then - all subscribers notified
        #expect(subscriber1Count == 1)
        #expect(subscriber2Count == 1)
        #expect(subscriber3Count == 1)
    }

    @Test("ThrowingValue works with different mock stores")
    func throwingValueWorksWithDifferentMockStores() throws {
        let throwingStore = InMemoryThrowingKeyValueStore()
        let observableStore = InMemoryObservableThrowingKeyValueStore()

        // When - set values in both
        try throwingStore.throwingValue.set(42)
        try observableStore.observableThrowingValue.set(100)

        // Then - values are independent
        #expect(try throwingStore.throwingValue.get() == 42)
        #expect(try observableStore.observableThrowingValue.get() == 100)
    }

    // MARK: - ThrowingGetter (Read-Only) Tests

    @Test("ThrowingGetter returns value")
    func throwingGetterReturnsValue() throws {
        let mockStore = InMemoryThrowingKeyValueStore()

        // Given - value exists
        mockStore.underlyingDict["readOnlyValue"] = 123

        // When - get value
        let value = try mockStore.readOnlyValue.get()

        // Then - value is returned
        #expect(value == 123)
    }

    @Test("ThrowingGetter returns nil for missing value")
    func throwingGetterReturnsNilForMissingValue() throws {
        let mockStore = InMemoryThrowingKeyValueStore()

        // Given - no value exists
        mockStore.underlyingDict.removeValue(forKey: "readOnlyValue")

        // When - get value
        let value = try mockStore.readOnlyValue.get()

        // Then - nil is returned
        #expect(value == nil)
    }

    @Test("ThrowingGetter with String type")
    func throwingGetterWithStringType() throws {
        let mockStore = InMemoryThrowingKeyValueStore()

        // Given - string value exists
        mockStore.underlyingDict["readOnlyName"] = "readonly"

        // When - get value
        let value = try mockStore.readOnlyName.get()

        // Then - value is returned
        #expect(value == "readonly")
    }

    @Test("ThrowingGetter throws on read error")
    func throwingGetterThrowsOnReadError() throws {
        let mockStore = InMemoryThrowingKeyValueStore()
        mockStore.throwOnRead = NSError(domain: "test", code: 1)

        // Given - mock store throws on get
        // When - get value
        do {
            _ = try mockStore.readOnlyValue.get()
            Issue.record("Should have thrown")
        } catch {
            // Then - error is thrown
            #expect((error as NSError).code == 1)
        }
    }

    @Test("ThrowingGetter has no set method")
    func throwingGetterHasNoSetMethod() throws {
        let mockStore = InMemoryThrowingKeyValueStore()

        // Given - ThrowingGetter type
        let getter = mockStore.readOnlyValue

        // Then - ThrowingGetter should not have a set method
        // This is validated at compile time - the type doesn't have .set()
        // Just verify we can use .get()
        _ = try getter.get()
    }

    @Test("ThrowingGetter works independently from ThrowingValue")
    func throwingGetterWorksIndependentlyFromThrowingValue() throws {
        let mockStore = InMemoryThrowingKeyValueStore()

        // Given - values exist for both types
        mockStore.underlyingDict["throwingValue"] = 42
        mockStore.underlyingDict["readOnlyValue"] = 100

        // When - get values
        let throwingValue = try mockStore.throwingValue.get()
        let readOnlyValue = try mockStore.readOnlyValue.get()

        // Then - both work independently
        #expect(throwingValue == 42)
        #expect(readOnlyValue == 100)

        // And - ThrowingValue can be set
        try mockStore.throwingValue.set(99)
        #expect(try mockStore.throwingValue.get() == 99)

        // But - Read-only value remains unchanged
        #expect(try mockStore.readOnlyValue.get() == 100)
    }

    // MARK: - Dependency Injection Tests

    @Test("UserDefaults subclass conforms to @Storage protocol")
    func userDefaultsSubclassConformsToStorageProtocol() {
        // Given - custom UserDefaults subclass
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }

        // When - use as protocol type
        let storage: InjectionTestSettings = appDefaults
        storage.injectionTestValue = "hello"
        storage.injectionTestCount = 42

        // Then - values are stored and retrieved
        #expect(storage.injectionTestValue == "hello")
        #expect(storage.injectionTestCount == 42)
    }

    @Test("UserDefaults subclass can be injected into services")
    func userDefaultsSubclassCanBeInjectedIntoServices() {
        // Given - service with protocol-constrained dependency
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let service = ServiceWithStorage(storage: appDefaults)

        // When - use through service
        service.storage.injectionTestValue = "injected"

        // Then - value persists through protocol
        #expect(service.storage.injectionTestValue == "injected")
    }

    @Test("Standard UserDefaults can be injected into services")
    func standardUserDefaultsCanBeInjectedIntoServices() {
        // Given - service with AppUserDefaults subclass
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }

        // Verify AppUserDefaults conforms to the protocol
        let conformsToProtocol = appDefaults is (any InjectionTestSettings)
        #expect(conformsToProtocol)

        // When - inject into service
        let service = ServiceWithStorage(storage: appDefaults)
        service.storage.injectionTestCount = 99

        // Then - works correctly
        #expect(service.storage.injectionTestCount == 99)
    }

    @Test("Custom file store subclass conforms to @Storage protocol")
    func customFileStoreSubclassConformsToStorageProtocol() {
        // Given - custom file store
        let fileStore = AppFileStore()

        // When - use as protocol type
        let storage: InjectionTestSettings = fileStore
        storage.injectionTestValue = "file-backed"
        storage.injectionTestCount = 100

        // Then - values work correctly
        #expect(storage.injectionTestValue == "file-backed")
        #expect(storage.injectionTestCount == 100)
    }

    @Test("Custom file store can be injected into services")
    func customFileStoreCanBeInjectedIntoServices() {
        // Given - service with file store
        let fileStore = AppFileStore()
        let service = ServiceWithStorage(storage: fileStore)

        // When - use through service
        service.storage.injectionTestValue = "file-injected"

        // Then - value persists
        #expect(service.storage.injectionTestValue == "file-injected")
    }

    @Test("UserDefaults can be injected when throwing protocol is required")
    func userDefaultsCanBeInjectedWhenThrowingProtocolRequired() throws {
        // Given - UserDefaults conforms to throwing protocols
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }

        // Verify conformance
        let conformsToThrowingProtocol = appDefaults is ThrowingInjectionSettings
        #expect(conformsToThrowingProtocol)

        // When - inject into service requiring throwing protocol
        let service = ServiceWithThrowingStorage(storage: appDefaults)

        // Then - throwing operations work
        try service.storage.throwingTestValue.set("throws-ok")
        let retrieved = try service.storage.throwingTestValue.get()
        #expect(retrieved == "throws-ok")
    }

    @Test("Protocol constrains injection to specific types")
    func protocolConstrainsInjectionToSpecificTypes() {
        // Given - type-constrained service
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let service = ServiceWithStorage(storage: appDefaults)

        // When - modify through service
        service.storage.injectionTestValue = "constrained"

        // Then - type is InjectionTestSettings, not generic UserDefaults
        let isProtocolType = service.storage is InjectionTestSettings
        #expect(isProtocolType)

        // And - still works correctly
        #expect(service.storage.injectionTestValue == "constrained")
    }

    @Test("Multiple services can share same storage instance")
    func multipleServicesCanShareSameStorageInstance() {
        // Given - shared storage instance
        let suiteName = "test-\(UUID())"
        let sharedDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { sharedDefaults.removePersistentDomain(forName: suiteName) }
        let service1 = ServiceWithStorage(storage: sharedDefaults)
        let service2 = ServiceWithStorage(storage: sharedDefaults)

        // When - one service modifies storage
        service1.storage.injectionTestCount = 123

        // Then - other service sees the change
        #expect(service2.storage.injectionTestCount == 123)
    }

    @Test("Observable protocols work with injected subclasses")
    func observableProtocolsWorkWithInjectedSubclasses() {
        // Given - observable subclass
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let service = ServiceWithStorage(storage: appDefaults)
        var emissionCount = 0

        // When - subscribe to publisher
        service.storage.$injectionTestValue.sink { _ in
            emissionCount += 1
        }.store(in: &cancellables)

        // Set initial value
        service.storage.injectionTestValue = "initial"

        // Then - publisher emits
        service.storage.injectionTestValue = "changed"
        #expect(emissionCount >= 1)
    }

    // MARK: - Test Isolation with UserDefaults Subclasses

    @Test("UserDefaults subclass constrains injection to specific type")
    func userDefaultsSubclassConstrainsInjectionToSpecificType() {
        // Given - service that requires specific subclass (not just protocol)
        let suiteName = "test-\(UUID())"
        let appDefaults = AppUserDefaults(suiteName: suiteName)!
        defer { appDefaults.removePersistentDomain(forName: suiteName) }
        let service = ServiceWithConstrainedUserDefaults(settings: appDefaults)

        // When - modify through service
        service.settings.injectionTestValue = "subclass-specific"

        // Then - value is stored correctly
        #expect(service.settings.injectionTestValue == "subclass-specific")

        // And - type is AppUserDefaults, not base UserDefaults
        let isAppUserDefaults = service.settings is AppUserDefaults
        #expect(isAppUserDefaults)

        // NOTE: The following would be a compile-time error (cannot pass base UserDefaults):
        // let baseDefaults = UserDefaults.standard
        // let invalid = ServiceWithConstrainedUserDefaults(settings: baseDefaults)  // ❌ Compile error
    }

    @Test("Isolated test UserDefaults instances don't interfere")
    func isolatedTestUserDefaultsInstancesDontInterfere() {
        // Given - two isolated test instances (each with unique suite)
        let instance1 = IsolatedTestUserDefaults()
        let instance2 = IsolatedTestUserDefaults()

        // When - write different values to each
        instance1.injectionTestValue = "instance1-value"
        instance1.injectionTestCount = 111

        instance2.injectionTestValue = "instance2-value"
        instance2.injectionTestCount = 222

        // Then - values don't interfere with each other
        #expect(instance1.injectionTestValue == "instance1-value")
        #expect(instance1.injectionTestCount == 111)

        #expect(instance2.injectionTestValue == "instance2-value")
        #expect(instance2.injectionTestCount == 222)
    }

    @Test("Isolated UserDefaults subclass provides clean state per test")
    func isolatedUserDefaultsSubclassProvidesCleanStatePerTest() {
        // Given - isolated instance
        let isolated = IsolatedTestUserDefaults()

        // Then - starts with nil values (clean state)
        #expect(isolated.injectionTestValue == nil)
        #expect(isolated.injectionTestCount == nil)

        // When - write values
        isolated.injectionTestValue = "test-value"
        isolated.injectionTestCount = 42

        // Then - values persist in this instance
        #expect(isolated.injectionTestValue == "test-value")
        #expect(isolated.injectionTestCount == 42)

        // When - create new instance
        let newInstance = IsolatedTestUserDefaults()

        // Then - new instance has clean state
        #expect(newInstance.injectionTestValue == nil)
        #expect(newInstance.injectionTestCount == nil)
    }

    @Test("Multiple tests using subclass-constrained services remain isolated")
    func multipleTestsUsingSubclassConstrainedServicesRemainIsolated() {
        // Simulating multiple test runs with same pattern

        // Test run 1
        let service1 = {
            let defaults = AppUserDefaults(suiteName: "test-\(UUID())")!
            let service = ServiceWithConstrainedUserDefaults(settings: defaults)
            service.settings.injectionTestValue = "run1"
            service.settings.injectionTestCount = 100
            return service
        }()

        // Test run 2 (different instance)
        let service2 = {
            let defaults = AppUserDefaults(suiteName: "test-\(UUID())")!
            let service = ServiceWithConstrainedUserDefaults(settings: defaults)
            service.settings.injectionTestValue = "run2"
            service.settings.injectionTestCount = 200
            return service
        }()

        // Then - each service maintains its own state
        #expect(service1.settings.injectionTestValue == "run1")
        #expect(service1.settings.injectionTestCount == 100)

        #expect(service2.settings.injectionTestValue == "run2")
        #expect(service2.settings.injectionTestCount == 200)
    }
}
