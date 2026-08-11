//
//  InMemoryKeyValueStore.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

/// A simple in-memory `KeyValueStoring` for EventHub tests. Holds values by reference (through
/// `set(_:forKey:)`'s `Any?`), and tracks `setCallCount` so persistence-throttling tests can assert
/// that writes are coalesced rather than performed per event.
final class InMemoryKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]
    private(set) var setCallCount = 0

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        setCallCount += 1
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
