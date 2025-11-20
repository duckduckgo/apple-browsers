//
//  KeyValueStoring.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

/// A wrapper for throwing get/set operations on storage values
///
/// Use this with `ThrowingKeyValueStoring` protocols to enable throwing access
/// while maintaining KeyPath compatibility.
///
/// ## Usage
/// ```swift
/// @Storage
/// protocol Settings: ThrowingKeyValueStoring {
///     var username: ThrowingValue<String> { get }
/// }
///
/// // Access with explicit error handling (returns optional)
/// let name: String? = try settings.username.get()
/// try settings.username.set("newName")
/// try settings.username.set(nil)  // Clear value
/// ```
public struct ThrowingValue<T> {

    private let getter: () throws -> T?
    private let setter: (T?) throws -> Void

    public init(getter: @escaping () throws -> T?, setter: @escaping (T?) throws -> Void) {
        self.getter = getter
        self.setter = setter
    }

    /// Get the value (throwing, returns optional)
    public func get() throws -> T? {
        return try getter()
    }

    /// Set the value (throwing, accepts optional for removal)
    public func set(_ value: T?) throws {
        try setter(value)
    }

    /// Throwing property accessor (returns optional)
    public var value: T? {
        get throws { try getter() }
    }
}

/// Wrapper for read-only throwing key-value store properties
///
/// Use `ThrowingGetter<T>` for properties that should be read-only and throw errors on access.
/// Unlike `ThrowingValue<T>`, this type does not provide a setter.
///
/// The `@Storage` macro automatically recognizes `ThrowingGetter<T>` as read-only - no `@ReadOnlyKey` annotation needed.
///
/// ## Usage
/// ```swift
/// @Storage
/// protocol Settings: ThrowingKeyValueStoring {
///     var readOnlyValue: ThrowingGetter<Int> { get }  // Automatically read-only
/// }
///
/// // Usage:
/// let value: Int? = try settings.readOnlyValue.get()
/// ```
public struct ThrowingGetter<T> {

    private let getter: () throws -> T?

    public init(getter: @escaping () throws -> T?) {
        self.getter = getter
    }

    /// Get the value (throwing, returns optional)
    public func get() throws -> T? {
        return try getter()
    }

    /// Throwing property accessor (returns optional)
    public var value: T? {
        get throws { try getter() }
    }
}

/// Key-value store that throws an error in case of an issue.
/// Use this for scenarios where reliability is a must.
///
/// ## Generic Access Methods
/// Properties are read-only with throwing getters. Use the generic `value(for:)` method for reading:
/// ```swift
/// let value: String? = try store.value(for: \.myProperty)
/// ```
///
/// For writing to value types (structs), use the `setValue(_:for:)` extension method.
/// For reference types (classes like UserDefaults), properties have setters that don't throw.
public protocol ThrowingKeyValueStoring {

    func object(forKey defaultName: String) throws -> Any?
    func set(_ value: Any?, forKey defaultName: String) throws
    func removeObject(forKey defaultName: String) throws

}

/// Key-value store compatible with base UserDefaults API
/// - Important: Use this for non-critical data that is easily recoverable if lost due to access issues.
/// Use MockKeyValueStore for testing.
///
/// Conforms to `ThrowingKeyValueStoring` with non-throwing implementations.
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

// For value types (structs), provide mutation helper
extension ThrowingKeyValueStoring {
    /// Set a strongly-typed value using a writable key path (for value types)
    /// Note: For reference types (classes), use property setters instead
    public func setValue<T>(_ value: T, for keyPath: WritableKeyPath<Self, T>) throws {
        var mutableSelf = self
        mutableSelf[keyPath: keyPath] = value
    }
}

/// Observable key-value store with throwing operations
///
/// This protocol combines `ThrowingKeyValueStoring` with observable support via Combine.
/// Properties have both getters and setters (not throwing) to enable observation.
/// The macro uses `try?` internally to handle errors silently.
///
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
/// Key-value store with KVO observation support via Combine publishers
///
/// This protocol extends `KeyValueStoring` to provide observable properties
/// that can be monitored for changes using Combine publishers.
///
/// ## KVO Requirements
/// For cross-process KVO to work correctly (e.g., between main app and extensions):
/// 1. The observed property must be declared as `@objc dynamic var` on UserDefaults extension
/// 2. The property name must exactly match the UserDefaults key name
/// 3. Keys cannot contain dots (`.`) as they break KVO key paths
///
/// ## Example Implementation
/// ```swift
/// extension UserDefaults {
///     @objc
///     dynamic var mySettingKey: String {
///         get {
///             value(forKey: "mySettingKey") as? String ?? "default"
///         }
///         set {
///             set(newValue, forKey: "mySettingKey")
///         }
///     }
///
///     var mySettingPublisher: AnyPublisher<String, Never> {
///         publisher(for: \.mySettingKey)
///             .eraseToAnyPublisher()
///     }
/// }
/// ```
///
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
