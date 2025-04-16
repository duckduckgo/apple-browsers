//
//  MockKeyValueStore.swift
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
import Persistence

public class MockKeyValueStore: KeyValueStoring {

    public var store = [String: Any?]()

    public init() { }

    public func object(forKey defaultName: String) -> Any? {
        return store[defaultName] as Any?
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        store[defaultName] = value
    }

    public func removeObject(forKey defaultName: String) {
        store[defaultName] = nil
    }

    public func clearAll() {
        store.removeAll()
    }
}

extension MockKeyValueStore: DictionaryRepresentable {

    public func dictionaryRepresentation() -> [String: Any] {
        return store as [String: Any]
    }
}
