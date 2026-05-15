//
//  DuckAiNativeStorageContainerMigration.swift
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

import Core
import Foundation
import os.log

/// Identifies which Duck.ai native-storage container is being migrated. The raw
/// value is suffixed onto the pixel name (see `PixelEvent.swift`).
enum DuckAiNativeStorageContainerMigrationLabel: String {
    case `default`
    case fireMode = "fire-mode"
}

/// Outcome events for `DuckAiNativeStorageContainerMigration`. Distinct from the
/// JS→native chat-data migration pixels (`duckAiNativeStorageMigration*`) — these
/// track the iOS-only relocation of the on-disk store from the app group container
/// into Application Support.
enum DuckAiNativeStorageContainerMigrationEvent {
    case notNeeded(label: DuckAiNativeStorageContainerMigrationLabel)
    case orphanRemoved(label: DuckAiNativeStorageContainerMigrationLabel)
    case success(label: DuckAiNativeStorageContainerMigrationLabel)
    case attemptFailed(label: DuckAiNativeStorageContainerMigrationLabel, error: Error)
    case gaveUp(label: DuckAiNativeStorageContainerMigrationLabel, error: Error?)
}

protocol DuckAiNativeStorageContainerMigrationPixelFiring {
    func fire(_ event: DuckAiNativeStorageContainerMigrationEvent)
}

struct NullDuckAiNativeStorageContainerMigrationPixelFiring: DuckAiNativeStorageContainerMigrationPixelFiring {
    func fire(_ event: DuckAiNativeStorageContainerMigrationEvent) {}
}

struct DuckAiNativeStorageContainerMigrationPixelAdapter: DuckAiNativeStorageContainerMigrationPixelFiring {
    func fire(_ event: DuckAiNativeStorageContainerMigrationEvent) {
        switch event {
        case .notNeeded(let label):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationNotNeeded(label: label.rawValue))
        case .orphanRemoved(let label):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationOrphanRemoved(label: label.rawValue))
        case .success(let label):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationSuccess(label: label.rawValue))
        case .attemptFailed(let label, let error):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationAttemptFailed(label: label.rawValue), error: error)
        case .gaveUp(let label, let error):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationGaveUp(label: label.rawValue), error: error)
        }
    }
}

/// One-time directory move from the shared app-group container into the app's
/// Application Support directory.
///
/// Files in App Group containers default to `NSFileProtectionComplete`, which
/// makes the SQLCipher DB and files folder inaccessible whenever the device
/// locks while the app is still alive — yielding 0xdead10cc terminations on
/// the next SQLite read (notably the background auto-clear path). Files in
/// the app sandbox default to `NSFileProtectionCompleteUntilFirstUserAuthentication`,
/// which stays available after first unlock.
///
/// The helper retries the move up to `maxAttempts` times across launches; after that
/// it marks the migration done and stops, accepting data loss rather than crashing
/// in a retry loop.
enum DuckAiNativeStorageContainerMigration {

    static let defaultMaxAttempts = 3

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo",
                                       category: "DuckAiNativeStorageContainerMigration")

    /// Ensures the directory at `url` exists and is excluded from iCloud
    static func excludeFromBackup(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var url = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
        } catch {
            Self.logger.error("[NativeStorage] failed to exclude \(url.lastPathComponent, privacy: .public) from backup: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moves `oldURL` to `newURL`, retrying on failure across launches.
    ///
    /// Persistence in `userDefaults`:
    /// - `migrationKey + ".done"` (Bool) — set when the migration reaches a terminal
    ///   state (success, no-op, orphan-cleaned, or `maxAttempts` exhausted).
    /// - `migrationKey + ".attempts"` (Int) — number of failed move attempts so far.
    ///   Cleared on success.
    ///
    /// `label` distinguishes the default vs. fire-mode container in logs and pixels.
    static func migrateIfNeeded(from oldURL: URL,
                                to newURL: URL,
                                migrationKey: String,
                                label: DuckAiNativeStorageContainerMigrationLabel,
                                userDefaults: UserDefaults = .standard,
                                fileManager: FileManager = .default,
                                pixelFiring: DuckAiNativeStorageContainerMigrationPixelFiring = NullDuckAiNativeStorageContainerMigrationPixelFiring(),
                                maxAttempts: Int = defaultMaxAttempts) {
        let doneKey = migrationKey + ".done"
        let attemptsKey = migrationKey + ".attempts"

        guard !userDefaults.bool(forKey: doneKey) else {
            Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] skipping: already done")
            return
        }

        let priorAttempts = userDefaults.integer(forKey: attemptsKey)
        Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] starting (prior attempts: \(priorAttempts)); old=\(oldURL.path, privacy: .public) new=\(newURL.path, privacy: .public)")

        guard fileManager.fileExists(atPath: oldURL.path) else {
            Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] no old directory; marking done")
            userDefaults.set(true, forKey: doneKey)
            userDefaults.removeObject(forKey: attemptsKey)
            pixelFiring.fire(.notNeeded(label: label))
            return
        }

        if fileManager.fileExists(atPath: newURL.path) {
            Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] new location already exists; removing orphan old")
            do {
                try fileManager.removeItem(at: oldURL)
                Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] orphan removed")
            } catch {
                Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] orphan removal failed: \(error.localizedDescription, privacy: .public)")
            }
            // New data is intact regardless of orphan removal outcome — mark done.
            userDefaults.set(true, forKey: doneKey)
            userDefaults.removeObject(forKey: attemptsKey)
            pixelFiring.fire(.orphanRemoved(label: label))
            return
        }

        do {
            try fileManager.createDirectory(at: newURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.moveItem(at: oldURL, to: newURL)
            Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] moved successfully")
            userDefaults.set(true, forKey: doneKey)
            userDefaults.removeObject(forKey: attemptsKey)
            pixelFiring.fire(.success(label: label))
        } catch {
            let attempt = priorAttempts + 1
            userDefaults.set(attempt, forKey: attemptsKey)
            if attempt >= maxAttempts {
                Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] move failed (attempt \(attempt)/\(maxAttempts)); giving up: \(error.localizedDescription, privacy: .public)")
                userDefaults.set(true, forKey: doneKey)
                pixelFiring.fire(.gaveUp(label: label, error: error))
            } else {
                Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] move failed (attempt \(attempt)/\(maxAttempts)); will retry next launch: \(error.localizedDescription, privacy: .public)")
                pixelFiring.fire(.attemptFailed(label: label, error: error))
            }
        }
    }
}
