//
//  InMemoryKeyValueStore.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine
import Persistence

/// In-memory implementation of KeyValueStoring with observation support.
/// Useful for testing and temporary storage scenarios.
open class InMemoryKeyValueStore: ObservableKeyValueStoring {

    public var store = [String: Any?]()
    public var objectWillChange = PassthroughSubject<String?, Never>()

    public init() { }

    public func updatesPublisher(forKey key: String) -> AnyPublisher<Void, Never> {
        objectWillChange.compactMap { change -> Void? in
            guard change == nil /* all */ || change == key else { return nil }
            return ()
        }.eraseToAnyPublisher()
    }

    public func object(forKey defaultName: String) -> Any? {
        return store[defaultName] as Any?
    }

    public func set(_ value: Any?, forKey key: String) {
        store[key] = value
        objectWillChange.send(key)
    }

    public func removeObject(forKey key: String) {
        store[key] = nil
        objectWillChange.send(key)
    }

    public func clearAll() {
        store.removeAll()
        objectWillChange.send(nil)
    }
}

extension InMemoryKeyValueStore: DictionaryRepresentable {
    public func dictionaryRepresentation() -> [String: Any] {
        return store as [String: Any]
    }
}

/// Backward compatibility typealias for existing code
public typealias MockKeyValueStore = InMemoryKeyValueStore
