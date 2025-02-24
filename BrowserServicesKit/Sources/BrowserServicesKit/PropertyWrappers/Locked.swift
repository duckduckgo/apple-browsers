//
//  Locked.swift
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

import Foundation

/// A property wrapper that provides thread-safe access to a value using an `NSLock`.
///
/// This wrapper ensures that each individual read (getter) and write (setter) is performed atomically.
///
/// **Limitations:**
///
/// - **Atomic Get/Set Only:**
///   The lock is applied only during the getter and setter. Compound operations—such as in-place mutations on a collection (e.g. `allowlist.append(newEntry)` or using `+=` on a scalar)—are not atomic.
///
/// - For mutable collections or compound operations, use dedicated methods that lock the entire operation or a thread-safe container.
///
@propertyWrapper
final class Locked<Value> {
    private var value: Value
    private let lock = NSLock()

    init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}
