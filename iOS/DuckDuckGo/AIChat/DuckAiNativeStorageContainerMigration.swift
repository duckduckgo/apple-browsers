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

import Foundation
import os.log

/// One-time directory move from the shared app-group container into the app's
/// Application Support directory.
///
/// Files in App Group containers default to `NSFileProtectionComplete`, which
/// makes the SQLCipher DB and files folder inaccessible whenever the device
/// locks while the app is still alive — yielding 0xdead10cc terminations on
/// the next SQLite read (notably the background auto-clear path). Files in
/// the app sandbox default to `NSFileProtectionCompleteUntilFirstUserAuthentication`,
/// which stays available after first unlock.
enum DuckAiNativeStorageContainerMigration {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo",
                                       category: "DuckAiNativeStorageContainerMigration")

    /// Moves `oldURL` to `newURL` once. The `migrationDoneKey` flag is set after
    /// the first attempt regardless of outcome (success, no-op, or failure) so
    /// subsequent launches do not retry.
    static func migrateIfNeeded(from oldURL: URL,
                                to newURL: URL,
                                migrationDoneKey: String,
                                userDefaults: UserDefaults = .standard,
                                fileManager: FileManager = .default) {
        guard !userDefaults.bool(forKey: migrationDoneKey) else {
            Self.logger.info("[NativeStorage] [\(migrationDoneKey, privacy: .public)] skipping: flag already set")
            return
        }
        defer { userDefaults.set(true, forKey: migrationDoneKey) }

        Self.logger.info("[NativeStorage] [\(migrationDoneKey, privacy: .public)] starting; old=\(oldURL.path, privacy: .public) new=\(newURL.path, privacy: .public)")

        guard fileManager.fileExists(atPath: oldURL.path) else {
            Self.logger.info("[NativeStorage] [\(migrationDoneKey, privacy: .public)] no old directory at \(oldURL.path, privacy: .public); marking done")
            return
        }

        if fileManager.fileExists(atPath: newURL.path) {
            Self.logger.info("[NativeStorage] [\(migrationDoneKey, privacy: .public)] new location already exists; removing orphan old at \(oldURL.path, privacy: .public)")
            do {
                try fileManager.removeItem(at: oldURL)
                Self.logger.info("[NativeStorage] [\(migrationDoneKey, privacy: .public)] orphan removed")
            } catch {
                Self.logger.error("[NativeStorage] [\(migrationDoneKey, privacy: .public)] orphan removal failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        do {
            try fileManager.createDirectory(at: newURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.moveItem(at: oldURL, to: newURL)
            Self.logger.info("[NativeStorage] [\(migrationDoneKey, privacy: .public)] moved \(oldURL.path, privacy: .public) → \(newURL.path, privacy: .public)")
        } catch {
            Self.logger.error("[NativeStorage] [\(migrationDoneKey, privacy: .public)] move failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
