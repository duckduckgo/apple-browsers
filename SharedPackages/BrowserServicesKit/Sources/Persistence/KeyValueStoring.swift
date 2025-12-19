//
//  KeyValueStoring.swift
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

// MARK: - Overview
//
// Type-safe key-value storage with automatic type conversion for UserDefaults and custom stores.
//
// ## Supported Value Types
//
// - **Primitive types**: String, Int, Bool, Double, Date, Data, Array, Dictionary (stored directly)
// - **RawRepresentable (Enums)**: Automatically converted to/from raw value
// - **Codable**: Automatically JSON-encoded to/decoded from Data
//
// ## Basic Usage
//
//     // 1. Define keys in a domain-specific enum
//     enum UserDefaultsKeys: String, StorageKeyDescribing {
//         case username
//         case userTheme = "user_theme"
//         case userPreferences = "user_prefs"
//     }
//
//     enum Theme: String { case light, dark }
//     struct UserPrefs: Codable { let fontSize: Int }
//
//     // 2. Create a StoringKeys struct
//     struct MyKeys: StoringKeys {
//         let username = StorageKey<String>(.username) // Primitive
//         let theme = StorageKey<Theme>(.userTheme) // RawRepresentable
//         let prefs = StorageKey<UserPrefs>(.userPreferences) // Codable
//     }
//
//     // 3. Use with dependency injection
//     class MyService {
//         let storage: any KeyedStoring<MyKeys>
//
//         init(storage: (any KeyedStoring<MyKeys>)? = nil) {
//             self.storage = storage ?? UserDefaults.standard.keyedStoring()
//         }
//
//         func updateUser() {
//             storage.username = "Alice"
//             storage.theme = .dark          // Stores "dark" string, returns Theme.dark
//             storage.prefs = UserPrefs(fontSize: 14)  // Auto-encoded to Data
//         }
//     }
//
//     // Production: inject UserDefaults
//     let service = MyService(storage: UserDefaults.standard.keyedStoring())
//     // Production: use standard UserDefaults
//     let service = MyService()
//
//     // Testing: inject mock store
//     let mockService = MyService(storage: InMemoryKeyValueStore().keyedStoring())
//
// ## Observable Storage
//
//     let storage: any ObservableKeyedStoring<MyKeys> = UserDefaults.standard.observableKeyedStoring()
//     storage.publisher(for: \.theme)
//         .sink { theme in print("Theme changed: \(theme)") }
//
// ## Patterns for Key Organization
//
// ### Enum-Based Keys:
//
//     // Define keys in centralized enum (e.g., UserDefaultsKeys.swift)
//     enum UserDefaultsKeys: String, StorageKeyDescribing {
//         case fireDialogSelectedOption = "fire-dialog_selectedOption"
//         case fireDialogIncludeHistory = "fire-dialog_includeHistory"
//     }
//
//     // Reference enum cases in StoringKeys struct
//     struct FireDialogSettings: StoringKeys {
//         let lastOption = StorageKey<Int>(UserDefaultsKeys.fireDialogSelectedOption)
//         let includeHistory = StorageKey<Bool>(UserDefaultsKeys.fireDialogIncludeHistory)
//     }
//
// Benefits: Type-safe key names, centralized definition, easy refactoring
//
// ## Default Values
//
// All storage values are optional by design (return `nil` if not set).
// Handle defaults at the call site:
//
//     let value = storage.setting ?? defaultValue
//
// ## Legacy Key Migration
//
//     enum UserDefaultsKeys: String, StorageKeyDescribing {
//         case userName = "user_name"
//     }
//
//     struct MyKeys: StoringKeys {
//         let userName = StorageKey<String>(UserDefaultsKeys.userName, migrateLegacyKey: "userName")
//     }
//     // First read attempts new key "user_name", falls back to legacy key "userName"
//
// ## Error Handling
//
// Use `ThrowingKeyedStoring` or `ObservableThrowingKeyedStoring` for error propagation:
//
//     let storage: ThrowingKeyedStorage<MyKeys> = ThrowingKeyedStorage(storage: customStore)
//     let value = try storage.value(for: \.someKey)  // Propagates encoding/decoding errors

import Combine
import Foundation

protocol StorageKeyProtocol {
    var rawValue: String { get }
}

public struct StorageKey<Value>: StorageKeyProtocol {
    let rawValue: String
    let migrateLegacyKey: String?

    internal init(
        _ rawValue: String,
        migrateLegacyKey: String? = nil,
        assertionHandler: (_ message: String) -> Void = { message in
            assertionFailure(message)
        }
    ) {
#if DEBUG
        if rawValue.contains(".") {
            assertionHandler("""
            Storage keys should not contain dots (.) as they break UserDefaults KVO observation.
            Key: '\(rawValue)'.
            Pass custom `assertionHandler: { _ in }` if absolutely necessary to override this behavior.
            """)
        }
#endif
        self.rawValue = rawValue
        self.migrateLegacyKey = migrateLegacyKey
    }

    public init(
        _ key: any StorageKeyDescribing,
        migrateLegacyKey: String? = nil,
        assertionHandler: (_ message: String) -> Void = { message in
            assertionFailure(message)
        }
    ) {
        self.init(key.rawValue, migrateLegacyKey: migrateLegacyKey, assertionHandler: assertionHandler)
    }
}

public protocol StoringKeys {
    init()
}

// MARK: - Storage Key Types

/// Protocol for enum-based storage key namespaces.
/// Enables platform-specific or domain-specific key collections similar to `FeatureFlagDescribing`.
public protocol StorageKeyDescribing: RawRepresentable where RawValue == String {
    /// The string key used for storage
    var rawValue: String { get }
}

public protocol KeyedStorageWrapper {
    associatedtype Keys: StoringKeys
}

@dynamicMemberLookup
public protocol ThrowingKeyedStoring<Keys>: KeyedStorageWrapper {
    subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? { get throws }
    func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws -> Value?

    func set<Value>(_ value: Value?, for keyPath: KeyPath<Keys, StorageKey<Value>>) throws

    func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws
}

/// Type-safe key-value storage with automatic type conversion.
/// Provides dynamic member lookup for accessing storage values via key paths.
@dynamicMemberLookup
public protocol KeyedStoring<Keys>: KeyedStorageWrapper {
    subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? { get nonmutating set }

    func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value?
    func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>)
}

// MARK: - Type Conversion Helpers

/// Decodes a value from storage, attempting multiple conversion strategies
private func decodeValue<Value>(from rawObject: Any?) throws -> Value? {
    guard let rawObject else { return nil }

    // Try direct cast first (primitives)
    if let value = rawObject as? Value {
        return value
    }

    // Try RawRepresentable conversion (enums)
    if let rawRepresentableType = Value.self as? any RawRepresentable.Type {
        func initRawRepresentable<T: RawRepresentable>(_ type: T.Type, rawValue: Any) -> T? {
            guard let rawValue = rawValue as? T.RawValue else { return nil }
            return type.init(rawValue: rawValue)
        }
        return initRawRepresentable(rawRepresentableType, rawValue: rawObject) as? Value
    }

    // Try Codable conversion (complex types)
    if let codableType = Value.self as? any Decodable.Type,
       let data = rawObject as? Data {
        return try JSONDecoder().decode(codableType, from: data) as? Value
    }

    return nil
}

/// Encodes a value for storage, using the appropriate strategy
private func encodeValue<Value>(_ value: Value) throws -> Any? {
    // Check if RawRepresentable (enums) - store raw value
    if let rawRepresentable = value as? any RawRepresentable {
        return rawRepresentable.rawValue
    }

    if PropertyListSerialization.propertyList(value, isValidFor: .binary) {
        return value
    }

    // Check if Codable - encode to Data
    if let encodable = value as? any Encodable {
        return try JSONEncoder().encode(encodable)
    }

    throw KeyValueStoringError.invalidValue(value)
}

enum KeyValueStoringError: Error, LocalizedError {
    case invalidValue(Any)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let value):
            return "Value '\(value)' is not Encodable, RawRepresentable or PropertyListSerializable"
        }
    }
}

@dynamicMemberLookup
public struct KeyedStorage<Keys: StoringKeys>: KeyedStoring, ThrowingKeyedStoring {
    let storage: KeyValueStoring

    public init(storage: KeyValueStoring) {
        self.storage = storage
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        get {
            value(for: keyPath)
        }
        nonmutating set {
            set(newValue, for: keyPath)
        }
    }

    public func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        let storageKey = storageKey(for: keyPath)

        // Try primary key first
        if let value: Value = try? decodeValue(from: storage.object(forKey: storageKey.rawValue)) {
            return value
        }

        // Try legacy key if available
        if let legacyKey = storageKey.migrateLegacyKey,
           let value: Value = try? decodeValue(from: storage.object(forKey: legacyKey)) {
            return value
        }

        return nil
    }

    public func set<Value>(_ value: Value?, for keyPath: KeyPath<Keys, StorageKey<Value>>) {
        guard let value else {
            removeValue(for: keyPath)
            return
        }
        let key = key(for: keyPath)

        do {
            if let encodedValue = try encodeValue(value) {
                storage.set(encodedValue, forKey: key)
            }
        } catch {
            assertionFailure("Failed to encode value for key '\(key)': \(error)")
        }
    }

    public func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) {
        let storageKey = storageKey(for: keyPath)
        storage.removeObject(forKey: storageKey.rawValue)
        // Also remove legacy key to ensure value is completely cleared
        if let legacyKey = storageKey.migrateLegacyKey {
            storage.removeObject(forKey: legacyKey)
        }
    }

}

@dynamicMemberLookup
public struct ThrowingKeyedStorage<Keys: StoringKeys>: ThrowingKeyedStoring {
    let storage: ThrowingKeyValueStoring

    public init(storage: ThrowingKeyValueStoring) {
        self.storage = storage
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        get throws {
            try value(for: keyPath)
        }
    }

    public func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws -> Value? {
        let storageKey = storageKey(for: keyPath)

        // Try primary key first
        if let value: Value = try decodeValue(from: try storage.object(forKey: storageKey.rawValue)) {
            return value
        }

        // Try legacy key if available
        if let legacyKey = storageKey.migrateLegacyKey,
           let value: Value = try decodeValue(from: try storage.object(forKey: legacyKey)) {
            return value
        }

        return nil
    }

    public func set<Value>(_ value: Value?, for keyPath: KeyPath<Keys, StorageKey<Value>>) throws {
        guard let value else {
            try removeValue(for: keyPath)
            return
        }
        let key = key(for: keyPath)

        if let encodedValue = try encodeValue(value) {
            try storage.set(encodedValue, forKey: key)
        }
    }

    public func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws {
        let storageKey = storageKey(for: keyPath)
        try storage.removeObject(forKey: storageKey.rawValue)
        // Also remove legacy key to ensure value is completely cleared
        if let legacyKey = storageKey.migrateLegacyKey {
            try storage.removeObject(forKey: legacyKey)
        }
    }
}

/// Observable key-value store with keyed access via key paths.
/// Combines `KeyedStoring` with `ObservableObject` for Combine-based change observation.
@dynamicMemberLookup
public protocol ObservableKeyedStoring<Keys>: KeyedStorageWrapper, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {

    typealias AnyCancellable = Combine.AnyCancellable
    typealias AnyPublisher = Combine.AnyPublisher
    typealias Publishers = Combine.Publishers

    subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? { get set }

    func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value?
    func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>)

    /// Creates a publisher for observing changes to a specific key path
    ///
    /// - Parameter keyPath: The key path to observe
    /// - Returns: A publisher that emits the current value when the key changes
    ///
    /// - Note: The publisher emits the current value immediately on subscription, then emits whenever the value changes
    func publisher<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> AnyPublisher<Value?, Never>

}

/// Observable key-value store with throwing operations.
/// Combines `ThrowingKeyedStoring` with `ObservableObject` for error propagation and change observation.
@dynamicMemberLookup
public protocol ObservableThrowingKeyedStoring<Keys>: KeyedStorageWrapper, AnyObject, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {

    typealias AnyCancellable = Combine.AnyCancellable
    typealias AnyPublisher = Combine.AnyPublisher
    typealias Publishers = Combine.Publishers

    subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? { get throws }
    func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws -> Value?

    func set<Value>(_ value: Value?, for keyPath: KeyPath<Keys, StorageKey<Value>>) throws
    func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws

    /// Creates a publisher for observing changes to a specific key path
    ///
    /// - Parameter keyPath: The key path to observe
    /// - Returns: A publisher that emits the current value when the key changes
    ///
    /// - Note: The publisher emits the current value immediately on subscription, then emits whenever the value changes
    func publisher<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> AnyPublisher<Value?, Never>

}

@dynamicMemberLookup
public final class ObservableKeyedStorage<Keys: StoringKeys>: ObservableKeyedStoring {
    let storage: any ObservableKeyValueStoring
    private var cancellable: AnyCancellable?

    public init(storage: any ObservableKeyValueStoring) {
        self.storage = storage
    }

    private func setupPublishersIfNeeded() {
        guard Thread.isMainThread, cancellable == nil else { return }

        // Create merged publisher for all keys and connect to objectWillChange
        let keys = allKeys()
        let mergedPublisher = keys.map { key in
            storage.updatesPublisher(forKey: key)
        }
        .reduce(Empty<Void, Never>().eraseToAnyPublisher()) { accumulated, next in
            accumulated.merge(with: next).eraseToAnyPublisher()
        }

        cancellable = mergedPublisher
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        get {
            value(for: keyPath)
        }
        set {
            set(newValue, for: keyPath)
        }
    }

    public func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        setupPublishersIfNeeded()
        let storageKey = storageKey(for: keyPath)

        // Try primary key first
        if let value: Value = try? decodeValue(from: storage.object(forKey: storageKey.rawValue)) {
            return value
        }

        // Try legacy key if available
        if let legacyKey = storageKey.migrateLegacyKey,
           let value: Value = try? decodeValue(from: storage.object(forKey: legacyKey)) {
            return value
        }

        return nil
    }

    public func set<Value>(_ value: Value?, for keyPath: KeyPath<Keys, StorageKey<Value>>) {
        setupPublishersIfNeeded()
        guard let value else {
            removeValue(for: keyPath)
            return
        }
        let key = key(for: keyPath)

        do {
            if let encodedValue = try encodeValue(value) {
                storage.set(encodedValue, forKey: key)
            }
        } catch {
            assertionFailure("Failed to encode value for key '\(key)': \(error)")
        }
    }

    public func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) {
        setupPublishersIfNeeded()
        let storageKey = storageKey(for: keyPath)
        storage.removeObject(forKey: storageKey.rawValue)
        // Also remove legacy key to ensure value is completely cleared
        if let legacyKey = storageKey.migrateLegacyKey {
            storage.removeObject(forKey: legacyKey)
        }
    }

    public func publisher<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> AnyPublisher<Value?, Never> {
        let key = key(for: keyPath)
        let currentValue = value(for: keyPath)

        return storage.updatesPublisher(forKey: key)
            .map { [weak self] _ -> Value? in
                self?.value(for: keyPath)
            }
            .prepend(currentValue)
            .eraseToAnyPublisher()
    }
}

@dynamicMemberLookup
public final class ObservableThrowingKeyedStorage<Keys: StoringKeys>: ObservableThrowingKeyedStoring {
    let storage: any ObservableThrowingKeyValueStoring
    private var cancellable: AnyCancellable?

    public init(storage: any ObservableThrowingKeyValueStoring) {
        self.storage = storage
    }

    private func setupPublishersIfNeeded() {
        guard Thread.isMainThread, cancellable == nil else { return }

        // Create merged publisher for all keys and connect to objectWillChange
        let keys = allKeys()
        let mergedPublisher = keys.map { key in
            storage.updatesPublisher(forKey: key)
        }
        .reduce(Empty<Void, Never>().eraseToAnyPublisher()) { accumulated, next in
            accumulated.merge(with: next).eraseToAnyPublisher()
        }

        cancellable = mergedPublisher
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<Keys, StorageKey<Value>>) -> Value? {
        get throws {
            try value(for: keyPath)
        }
    }

    public func value<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws -> Value? {
        setupPublishersIfNeeded()
        let storageKey = storageKey(for: keyPath)

        // Try primary key first
        if let value: Value = try decodeValue(from: try storage.object(forKey: storageKey.rawValue)) {
            return value
        }

        // Try legacy key if available
        if let legacyKey = storageKey.migrateLegacyKey,
           let value: Value = try decodeValue(from: try storage.object(forKey: legacyKey)) {
            return value
        }

        return nil
    }

    public func set<Value>(_ value: Value?, for keyPath: KeyPath<Keys, StorageKey<Value>>) throws {
        setupPublishersIfNeeded()
        guard let value else {
            try removeValue(for: keyPath)
            return
        }
        let key = key(for: keyPath)

        if let encodedValue = try encodeValue(value) {
            try storage.set(encodedValue, forKey: key)
        }
    }

    public func removeValue<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) throws {
        setupPublishersIfNeeded()
        let storageKey = storageKey(for: keyPath)
        try storage.removeObject(forKey: storageKey.rawValue)
        // Also remove legacy key to ensure value is completely cleared
        if let legacyKey = storageKey.migrateLegacyKey {
            try storage.removeObject(forKey: legacyKey)
        }
    }

    public func publisher<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> AnyPublisher<Value?, Never> {
        let key = key(for: keyPath)
        let currentValue = try? value(for: keyPath)

        return storage.updatesPublisher(forKey: key)
            .map { [weak self] _ -> Value? in
                try? self?.value(for: keyPath)
            }
            .prepend(currentValue)
            .eraseToAnyPublisher()
    }
}

extension KeyValueStoring {
    public func keyedStoring<Keys: StoringKeys>(for keysType: Keys.Type = Keys.self) -> some KeyedStoring<Keys> {
        KeyedStorage(storage: self)
    }
}

extension ObservableKeyValueStoring {
    public func observableKeyedStoring<Keys: StoringKeys>(for keysType: Keys.Type = Keys.self) -> some ObservableKeyedStoring<Keys> {
        ObservableKeyedStorage(storage: self)
    }
}

extension UserDefaults {
    public func keyedStoring<Keys: StoringKeys>() -> some KeyedStoring<Keys> {
        KeyedStorage(storage: self)
    }

    public func observableKeyedStoring<Keys: StoringKeys>() -> some ObservableKeyedStoring<Keys> {
        ObservableKeyedStorage(storage: self)
    }
}

private var keysCache = [ObjectIdentifier: any StoringKeys]()
private var allKeysCache = [ObjectIdentifier: [String]]()

extension KeyedStorageWrapper {
    private func cachedKeysCreatingIfNeeded() -> Keys {
        dispatchPrecondition(condition: .onQueue(.main))

        let keysId = ObjectIdentifier(Keys.self)
        if let cachedKeys = keysCache[keysId] as? Keys {
            return cachedKeys
        } else {
            let keys = Keys()
            keysCache[keysId] = keys
            return keys
        }
    }

    func key<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> String {
        let keys: Keys
        if Thread.isMainThread {
            keys = cachedKeysCreatingIfNeeded()
        } else {
            keys = Keys()
        }
        let key = keys[keyPath: keyPath]
        return key.rawValue
    }

    func storageKey<Value>(for keyPath: KeyPath<Keys, StorageKey<Value>>) -> StorageKey<Value> {
        let keys: Keys
        if Thread.isMainThread {
            keys = cachedKeysCreatingIfNeeded()
        } else {
            keys = Keys()
        }
        return keys[keyPath: keyPath]
    }

    func allKeys() -> [String] {
        dispatchPrecondition(condition: .onQueue(.main))

        let keysId = ObjectIdentifier(Keys.self)

        // Check cache first
        if let cached = allKeysCache[keysId] {
            return cached
        }

        // Get cached Keys instance
        let keysInstance = cachedKeysCreatingIfNeeded()

        // Use reflection to extract all StorageKey properties
        let mirror = Mirror(reflecting: keysInstance)

        var keys: [String] = []
        for child in mirror.children {
            // Cast to protocol to access rawValue regardless of generic type
            if let storageKey = child.value as? StorageKeyProtocol {
                keys.append(storageKey.rawValue)
            }
        }

        // Cache the result
        allKeysCache[keysId] = keys
        return keys
    }
}

/// Key-value store with throwing operations for error propagation.
/// Use for scenarios requiring explicit error handling.
public protocol ThrowingKeyValueStoring {

    func object(forKey defaultName: String) throws -> Any?
    func set(_ value: Any?, forKey defaultName: String) throws
    func removeObject(forKey defaultName: String) throws

}

/// Key-value store compatible with UserDefaults API.
/// Non-throwing variant of `ThrowingKeyValueStoring` for simple storage scenarios.
public protocol KeyValueStoring: ThrowingKeyValueStoring {

    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)

}

// Default implementations of throwing methods that delegate to non-throwing versions
extension KeyValueStoring {
    public func object(forKey defaultName: String) throws -> Any? {
        return object(forKey: defaultName)
    }

    public func set(_ value: Any?, forKey defaultName: String) throws {
        set(value, forKey: defaultName)
    }

    public func removeObject(forKey defaultName: String) throws {
        removeObject(forKey: defaultName)
    }
}

// Generic helper methods for accessing properties
extension ThrowingKeyValueStoring {
    /// Get a strongly-typed value using a key path
    public func value<T>(for keyPath: KeyPath<Self, T>) throws -> T {
        return self[keyPath: keyPath]
    }
}

/// Observable key-value store with throwing operations.
/// Combines `ThrowingKeyValueStoring` with `ObservableObject` for error propagation and change observation.
public protocol ObservableThrowingKeyValueStoring: AnyObject, ThrowingKeyValueStoring, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {

    typealias AnyCancellable = Combine.AnyCancellable
    typealias AnyPublisher = Combine.AnyPublisher
    typealias Publishers = Combine.Publishers

    /// Creates a publisher for observing changes to a specific key
    ///
    /// - Parameter key: The key to observe
    /// - Returns: A publisher that emits Void when the key's value changes after subscription
    ///
    /// - Note: The publisher only emits when values change after subscription, not the current value on subscription
    func updatesPublisher(forKey key: String) -> AnyPublisher<Void, Never>

}
/// Key-value store with KVO observation support via Combine publishers.
///
/// **KVO Requirements for UserDefaults:**
/// - Properties must be `@objc dynamic var`
/// - Property name must exactly match the UserDefaults key name  
/// - Keys cannot contain dots (`.`) as they break KVO key paths
public protocol ObservableKeyValueStoring: AnyObject, KeyValueStoring, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {

    typealias AnyCancellable = Combine.AnyCancellable
    typealias AnyPublisher = Combine.AnyPublisher
    typealias Publishers = Combine.Publishers

    /// Creates a publisher for observing changes to a specific key
    ///
    /// - Parameter key: The key to observe
    /// - Returns: A publisher that emits Void when the key's value changes after subscription
    ///
    /// - Note: The publisher only emits when values change after subscription, not the current value on subscription
    func updatesPublisher(forKey key: String) -> AnyPublisher<Void, Never>

}
public protocol ConstrainedObservableObject: ObservableKeyValueStoring {
    static var observableStorageProtocolType: Any.Type { get }
}
