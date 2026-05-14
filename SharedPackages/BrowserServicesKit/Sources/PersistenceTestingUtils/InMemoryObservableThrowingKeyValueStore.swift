//
//  InMemoryObservableThrowingKeyValueStore.swift
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
import Persistence

/// In-memory implementation of ObservableThrowingKeyValueStoring with observation support.
/// Useful for testing throwing operations with change notifications.
open class InMemoryObservableThrowingKeyValueStore: ObservableThrowingKeyValueStoring {

    /// Direct access to underlying storage dictionary for test setup and assertions
    public var underlyingDict: [String: Any]

    /// Error to throw on set operations (if not nil)
    public var throwOnSet: Error?

    /// Error to throw on get operations (if not nil)
    public var throwOnRead: Error?

    /// Error to throw on remove operations (if not nil)
    public var throwOnRemove: Error?

    /// Controls whether get operations should throw errors (for backward compatibility)
    public var shouldThrowOnGet: Bool {
        get { throwOnRead != nil }
        set { throwOnRead = newValue ? MockError.getError : nil }
    }

    /// Controls whether set operations should throw errors (for backward compatibility)
    public var shouldThrowOnSet: Bool {
        get { throwOnSet != nil }
        set { throwOnSet = newValue ? MockError.setError : nil }
    }

    /// Controls whether remove operations should throw errors (for backward compatibility)
    public var shouldThrowOnRemove: Bool {
        get { throwOnRemove != nil }
        set { throwOnRemove = newValue ? MockError.removeError : nil }
    }

    public var objectWillChange = ObservableObjectPublisher()

    // Internal subject for key-specific change notifications
    private var keyChanges = PassthroughSubject<String?, Never>()

    public enum MockError: Error, Equatable {
        case getError
        case setError
        case removeError
    }

    public init(underlyingDict: [String: Any] = [:]) {
        self.underlyingDict = underlyingDict
    }

    /// Initializer that throws an error immediately - useful for testing initialization failures
    public init(throwOnInit error: Error?, underlyingDict: [String: Any] = [:]) throws {
        self.underlyingDict = underlyingDict
        try error.map { throw $0 }
    }

    public func updatesPublisher(forKey key: String) -> AnyPublisher<Void, Never> {
        keyChanges.compactMap { change -> Void? in
            guard change == nil /* all */ || change == key else { return nil }
            return ()
        }.eraseToAnyPublisher()
    }

    public func object(forKey key: String) throws -> Any? {
        if let throwOnRead {
            throw throwOnRead
        }
        return underlyingDict[key]
    }

    public func set(_ value: Any?, forKey key: String) throws {
        if let throwOnSet {
            throw throwOnSet
        }
        underlyingDict[key] = value
        objectWillChange.send()
        keyChanges.send(key)
    }

    public func removeObject(forKey key: String) throws {
        if let throwOnRemove {
            throw throwOnRemove
        }
        underlyingDict.removeValue(forKey: key)
        objectWillChange.send()
        keyChanges.send(key)
    }
}

/// Backward compatibility typealias for existing code
public typealias MockObservableThrowingKeyValueStore = InMemoryObservableThrowingKeyValueStore
