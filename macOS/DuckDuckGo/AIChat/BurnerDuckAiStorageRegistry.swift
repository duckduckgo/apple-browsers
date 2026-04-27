//
//  BurnerDuckAiStorageRegistry.swift
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

import AIChat
import Foundation
import WebKit

/// Maps a burner window's `WKWebsiteDataStore` to an in-memory Duck.ai storage handler.
///
/// Burner windows that share the same data store share the same in-memory handler;
/// different burner sessions get fully isolated handlers. A non-persistent
/// `WKWebsiteDataStore` reference is the natural identity for a "fire window session",
/// so we key off `ObjectIdentifier(dataStore)` and let storage live for as long as the
/// data store does.
///
/// Reads and writes are guarded by `NSLock` so the user script can resolve a handler
/// from its background message queue while registration happens on the main actor.
final class BurnerDuckAiStorageRegistry {

    static let shared = BurnerDuckAiStorageRegistry()

    private let lock = NSLock()
    private var handlers: [ObjectIdentifier: DuckAiNativeStorageHandling] = [:]

    private init() {}

    /// Returns the existing handler for the given data store, or installs `make()`'s
    /// result and returns it. `make` is invoked at most once per data store.
    func handler(for dataStore: WKWebsiteDataStore,
                 makeIfAbsent make: () -> DuckAiNativeStorageHandling) -> DuckAiNativeStorageHandling {
        let key = ObjectIdentifier(dataStore)
        lock.lock()
        defer { lock.unlock() }
        if let existing = handlers[key] {
            return existing
        }
        let new = make()
        handlers[key] = new
        return new
    }

    func handler(for dataStore: WKWebsiteDataStore) -> DuckAiNativeStorageHandling? {
        let key = ObjectIdentifier(dataStore)
        lock.lock()
        defer { lock.unlock() }
        return handlers[key]
    }

    func unregister(_ dataStore: WKWebsiteDataStore) {
        unregister(ObjectIdentifier(dataStore))
    }

    func unregister(_ key: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: key)
    }
}

extension BurnerMode {
    /// Resolves (lazily creating if needed) the in-memory Duck.ai storage handler scoped
    /// to this burner mode's data store. Returns `nil` for `.regular`.
    func duckAiFireModeStorageHandler() -> DuckAiNativeStorageHandling? {
        switch self {
        case .regular:
            return nil
        case .burner(let dataStore):
            return BurnerDuckAiStorageRegistry.shared.handler(for: dataStore) {
                InMemoryDuckAiNativeStorageHandler()
            }
        }
    }
}
