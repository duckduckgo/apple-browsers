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

    private let lock = NSLock()
    private var handlers: [ObjectIdentifier: DuckAiNativeStorageHandling] = [:]
    private let diskHandler: DuckAiNativeStorageHandling?

    /// `diskHandler` is passed to each in-memory handler as its `seedSource` so the small
    /// set of cross-mode consent keys (see `DuckAiNativeStorageConsent.entryKeys`) remains
    /// visible to fire windows even after the FE issues `replaceAllEntries`.
    init(diskHandler: DuckAiNativeStorageHandling? = nil) {
        self.diskHandler = diskHandler
    }

    /// Returns or lazily creates the in-memory handler scoped to `burnerMode`'s data store.
    /// Returns `nil` for `.regular`.
    func handler(for burnerMode: BurnerMode) -> DuckAiNativeStorageHandling? {
        guard case .burner(let dataStore) = burnerMode else { return nil }
        let key = ObjectIdentifier(dataStore)
        lock.lock()
        defer { lock.unlock() }
        if let existing = handlers[key] {
            return existing
        }
        let new = try? DuckAiNativeStorageHandler(.memory(seedSource: diskHandler))
        guard let new else { return nil }
        handlers[key] = new
        return new
    }

    func unregister(_ key: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: key)
    }
}
