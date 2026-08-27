//
//  LegacyPixelStateMigration.swift
//  DuckDuckGo
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
import os.log

/// A legacy pixel store, viewed as a snapshot.
///
/// `ThrowingKeyValueStoring` cannot enumerate keys and the migration has to visit all of them, so
/// each backing store supplies its own snapshot instead.
public protocol LegacyPixelLastFireDateSource {
    func allLastFireDates() throws -> [String: Date]
}

/// Carries the legacy pixel throttling state into PixelKit's store, once.
///
/// Legacy `DailyPixel`, `UniquePixel` and `Pixel`'s debounce each kept their own suite keyed by the
/// bare `Pixel.Event.name` with a `Date` value. PixelKit keys
/// `com.duckduckgo.network-protection.pixel.<name>` and stores a `[frequencyMapKey: Date]` map. The
/// name part matches, because `Pixel.Event`'s `platformSuffixPolicy` is `.standard` and so keeps the
/// `_ios_phone` marker out of the throttling key. That makes this a key-for-key copy.
///
/// Without it, the release that migrates re-fires every once-ever pixel for the whole install base
/// and every daily pixel once extra.
///
/// Runs per process against that process's own stores: the browser and the VPN tunnel keep separate
/// legacy stores (the tunnel replaces `DailyPixel.storage` and `UniquePixel.storage` with
/// `KeyValueFileStore`s in the VPN app group), so each drives its own instance.
public struct LegacyPixelStateMigration {

    public static let completionFlagKey = "com.duckduckgo.pixel.legacy-state-migration.completed"

    /// PixelKit's `userDefaultsKeyName(forPixelName:)`. Duplicated rather than exposed, because
    /// making it public would invite callers to write PixelKit's storage directly.
    private static let pixelKitKeyPrefix = "com.duckduckgo.network-protection.pixel."

    private let destination: ThrowingKeyValueStoring
    private let sources: [(store: LegacyPixelLastFireDateSource?, mapKey: String)]
    private let completionFlagStore: ThrowingKeyValueStoring
    private let logger = Logger(subsystem: "PixelMigration", category: "LegacyPixelStateMigration")

    /// - Parameters:
    ///   - destination: the same store passed to `PixelKit.setUp` as `defaults` for this process.
    ///   - dailyStore: `DailyPixel.storage`, migrated to the `daily` map key, which every daily
    ///     frequency (`.legacyDailyNoSuffix`, `.dailyAndCount`, `.legacyDailyAndCount`,
    ///     `.dailyAndStandard`) throttles under.
    ///   - uniqueStore: `UniquePixel.storage`, migrated to `uniqueByName`, shared by
    ///     `.uniqueByName` and `.legacyInitial`.
    ///   - debounceStore: `Pixel.storage`, migrated to `debounce`.
    ///   - completionFlagStore: where the run-once flag lives.
    public init(destination: ThrowingKeyValueStoring,
                dailyStore: LegacyPixelLastFireDateSource?,
                uniqueStore: LegacyPixelLastFireDateSource?,
                debounceStore: LegacyPixelLastFireDateSource?,
                completionFlagStore: ThrowingKeyValueStoring) {
        self.destination = destination
        self.sources = [(dailyStore, "daily"),
                        (uniqueStore, "uniqueByName"),
                        (debounceStore, "debounce")]
        self.completionFlagStore = completionFlagStore
    }

    public func run() {
        guard !hasAlreadyRun else { return }

        var migrated = 0
        for source in sources {
            guard let store = source.store else { continue }
            let dates: [String: Date]
            do {
                dates = try store.allLastFireDates()
            } catch {
                // Fail open. Losing one store's state costs one extra fire per pixel in it;
                // abandoning the migration would cost that for every store.
                logger.error("Could not read a legacy pixel store: \(error.localizedDescription, privacy: .public)")
                continue
            }

            for (pixelName, date) in dates {
                do {
                    try merge(date: date, mapKey: source.mapKey, pixelName: pixelName)
                    migrated += 1
                } catch {
                    logger.error("Could not migrate \(pixelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        logger.log("Migrated \(migrated, privacy: .public) legacy pixel last-fire dates into PixelKit")
        try? completionFlagStore.set(true, forKey: Self.completionFlagKey)
    }

    private var hasAlreadyRun: Bool {
        // Fail closed: if reading the flag throws, skip, rather than risk overwriting newer
        // PixelKit state with stale legacy dates on every launch. A missing flag is not a throw,
        // just a normal `nil` decode, and means only that this is the first run.
        do {
            return (try completionFlagStore.object(forKey: Self.completionFlagKey) as? Bool) ?? false
        } catch {
            return true
        }
    }

    private func merge(date: Date, mapKey: String, pixelName: String) throws {
        let key = Self.pixelKitKeyPrefix + pixelName
        var map = (try destination.object(forKey: key) as? [String: Date]) ?? [:]
        // An entry PixelKit itself wrote wins: it is newer than anything the legacy store holds.
        guard map[mapKey] == nil else { return }
        map[mapKey] = date
        try destination.set(map, forKey: key)
    }
}

/// A `UserDefaults` suite as a snapshot source. All three browser-side legacy stores are suites.
public struct UserDefaultsLegacyPixelStore: LegacyPixelLastFireDateSource {
    private let defaults: UserDefaults
    private let suiteName: String

    public init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
        self.suiteName = suiteName
    }

    public func allLastFireDates() throws -> [String: Date] {
        // `persistentDomain(forName:)` returns only this suite's own keys. `dictionaryRepresentation()`
        // also merges in `NSGlobalDomain` and the registration domain.
        //
        // `Date` values only. Compound `name:<error values>` keys have no PixelKit equivalent.
        // They are dropped here.
        (defaults.persistentDomain(forName: suiteName) ?? [:]).compactMapValues { $0 as? Date }
    }
}

/// A `KeyValueFileStore` as a snapshot source, for the VPN tunnel's file-backed legacy stores.
public struct KeyValueFileStoreLegacyPixelStore: LegacyPixelLastFireDateSource {
    private let store: KeyValueFileStore

    public init(_ store: KeyValueFileStore) {
        self.store = store
    }

    public func allLastFireDates() throws -> [String: Date] {
        try store.allObjects().compactMapValues { $0 as? Date }
    }
}
