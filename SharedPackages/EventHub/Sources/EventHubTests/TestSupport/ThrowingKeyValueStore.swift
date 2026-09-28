//
//  ThrowingKeyValueStore.swift
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

/// A `ThrowingKeyValueStoring` whose individual operations can be made to throw, so the store's
/// fail-safe boundaries can be exercised. `InMemoryKeyValueStore` cannot: it conforms to the
/// non-throwing `KeyValueStoring`, so its operations never fail.
final class ThrowingKeyValueStore: ThrowingKeyValueStoring {
    struct StoreError: Error {}

    private var storage: [String: Any] = [:]

    var throwOnRead = false
    var throwOnWrite = false
    var throwOnRemove = false

    init(storage: [String: Any] = [:]) {
        self.storage = storage
    }

    func object(forKey defaultName: String) throws -> Any? {
        if throwOnRead { throw StoreError() }
        return storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) throws {
        if throwOnWrite { throw StoreError() }
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) throws {
        if throwOnRemove { throw StoreError() }
        storage.removeValue(forKey: defaultName)
    }
}
