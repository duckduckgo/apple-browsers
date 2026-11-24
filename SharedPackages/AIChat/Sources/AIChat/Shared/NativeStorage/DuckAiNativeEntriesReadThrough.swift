//
//  DuckAiNativeEntriesReadThrough.swift
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

import Combine
import Foundation

/// Shows a persistent store's entries through fire storage that has none of its own.
public final class DuckAiNativeEntriesReadThrough {

    /// Settings fire storage starts on but can clear for itself.
    static let settingKeys: Set<String> = [DuckAiNativeStorageReservedEntryKeys.defaultDuckaiModel.rawValue]
    /// Consent always reads through, so it can't be withdrawn in fire storage alone.
    static let keys = DuckAiNativeStorageConsent.entryKeys.union(settingKeys)

    private let seedSource: DuckAiNativeStorageHandling
    private let lock = NSLock()
    private var clearedKeys: Set<String> = []

    public init(seedSource: DuckAiNativeStorageHandling) {
        self.seedSource = seedSource
    }

    /// Emits after `seedSource` writes or deletes an entry that reads through.
    public static func seedEntryUpdates(from seedSource: DuckAiNativeStorageHandling) -> AnyPublisher<DuckAiNativeStorageReservedEntryKeys, Never> {
        guard let observing = seedSource as? DuckAiNativeEntriesObserving else { return Empty().eraseToAnyPublisher() }
        return observing.reservedEntryUpdatesPublisher
            .filter { keys.contains($0.rawValue) }
            .eraseToAnyPublisher()
    }

    /// The seed's value for an entry fire storage doesn't hold.
    public func seedEntry(forKey key: String) -> Any? {
        guard readsThrough(key) else { return nil }
        return try? seedSource.getEntry(key: key)
    }

    /// `entries` with the seed's values added for the entries they lack.
    public func entries(fillingIn entries: [String: Any]) -> [String: Any] {
        var result = entries
        for key in Self.keys where result[key] == nil {
            result[key] = seedEntry(forKey: key)
        }
        return result
    }

    public func entryDeleted(key: String) {
        guard Self.settingKeys.contains(key) else { return }
        lock.lock()
        defer { lock.unlock() }
        clearedKeys.insert(key)
    }

    /// A wiped fire storage starts over on the seed's settings.
    public func allEntriesDeleted() {
        lock.lock()
        defer { lock.unlock() }
        clearedKeys.removeAll()
    }

    private func readsThrough(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Self.keys.contains(key) && !clearedKeys.contains(key)
    }
}
