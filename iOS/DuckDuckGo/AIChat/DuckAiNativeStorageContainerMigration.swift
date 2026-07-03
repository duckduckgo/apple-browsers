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
import Persistence
import UIKit
import os.log

/// One-time move of a Duck.ai container from the shared App Group into the
/// app's Application Support directory.
///
/// App Group files default to `NSFileProtectionComplete`, which makes the DB
/// inaccessible whenever the device locks while the app is alive (0xdead10cc
/// on the next SQLite read). The app sandbox defaults to
/// `NSFileProtectionCompleteUntilFirstUserAuthentication`, which stays readable
/// after first unlock.
///
/// Persistent state is owned by `MigrationStateStore`.
struct DuckAiNativeStorageContainerMigration: DuckAiNativeStorageContainerMigrating {

    static let defaultMaxAttempts = 3
    typealias ProtectionDispatcher = (@escaping () -> Void) -> Void

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo",
                                       category: "DuckAiNativeStorageContainerMigration")

    let oldURL: URL
    let newURL: URL
    let label: DuckAiNativeStorageContainerMigrationLabel
    let fileManager: FileManager
    let pixelFiring: DuckAiNativeStorageContainerMigrationPixelFiring
    let isProtectedDataAvailable: () -> Bool
    let maxAttempts: Int

    /// When true, the protected-data gate only guards the relocation; completed /
    /// not-needed migrations proceed on locked launches. When false, the legacy
    /// behavior applies (any locked launch defers). Phased-rollout / kill switch.
    let lockedLaunchFixEnabled: Bool

    private let stateStore: MigrationStateStore
    private let protectionDispatcher: ProtectionDispatcher

    init(oldURL: URL,
         newURL: URL,
         migrationKey: String,
         label: DuckAiNativeStorageContainerMigrationLabel,
         keyValueStore: ThrowingKeyValueStoring,
         fileManager: FileManager = .default,
         pixelFiring: DuckAiNativeStorageContainerMigrationPixelFiring = NullDuckAiNativeStorageContainerMigrationPixelFiring(),
         isProtectedDataAvailable: @escaping () -> Bool = { DuckAiNativeStorageContainerMigration.defaultIsProtectedDataAvailable() },
         maxAttempts: Int = DuckAiNativeStorageContainerMigration.defaultMaxAttempts,
         lockedLaunchFixEnabled: Bool = true,
         protectionDispatcher: @escaping ProtectionDispatcher = { work in
             DispatchQueue.global(qos: .utility).async(execute: work)
         }) {
        self.oldURL = oldURL
        self.newURL = newURL
        self.label = label
        self.fileManager = fileManager
        self.pixelFiring = pixelFiring
        self.isProtectedDataAvailable = isProtectedDataAvailable
        // 0 / negative would give up on the first failure.
        self.maxAttempts = max(1, maxAttempts)
        self.lockedLaunchFixEnabled = lockedLaunchFixEnabled
        self.stateStore = MigrationStateStore(keyValueStore: keyValueStore, migrationKey: migrationKey)
        self.protectionDispatcher = protectionDispatcher
    }

    // MARK: - Entry point

    @discardableResult
    func run() -> DuckAiNativeStorageContainerMigrationOutcome {
        if !lockedLaunchFixEnabled, let deferred = deferIfProtectedDataUnavailable() {
            return deferred
        }

        do {
            return try performMigration()
        } catch let kvError as MigrationStateStore.ReadError {
            Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] key-value store read failed; deferring: \(kvError.underlying.localizedDescription, privacy: .public)")
            pixelFiring.fire(.keyValueStoreReadFailed(label: label, error: kvError.underlying))
            return .skip
        } catch {
            assertionFailure("Unexpected throw from performMigration: \(error)")
            Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] unexpected migration error; deferring: \(error.localizedDescription, privacy: .public)")
            return .skip
        }
    }

    private func deferIfProtectedDataUnavailable() -> DuckAiNativeStorageContainerMigrationOutcome? {
        guard !isProtectedDataAvailable() else { return nil }
        Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] protected data unavailable; deferring")
        pixelFiring.fire(.protectedDataUnavailable(label: label))
        return .skip
    }

    private func performMigration() throws -> DuckAiNativeStorageContainerMigrationOutcome {
        var state = try stateStore.load()
        resetExhaustedAttemptsIfNeeded(&state)

        if state.isMigrated {
            ensureProtection(priorAttempts: state.protectionAttempts)
            return .proceed
        }

        guard fileManager.fileExists(atPath: oldURL.path) else {
            Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] no old directory; marking done")
            stateStore.markMigrated()
            pixelFiring.fire(.notNeeded(label: label))
            ensureProtection(priorAttempts: state.protectionAttempts)
            return .proceed
        }

        if lockedLaunchFixEnabled, let deferred = deferIfProtectedDataUnavailable() {
            return deferred
        }

        Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] starting (prior attempts: \(state.attempts)); old=\(oldURL.path, privacy: .public) new=\(newURL.path, privacy: .public)")

        if fileManager.fileExists(atPath: newURL.path) {
            // Destination exists without `migrated`. If data is present, treat
            // it as a possibly-partial copy: claim the destination but keep the
            // source for recovery. If empty, it's scaffolding from a prior
            // `excludeFromBackup` on a skipped launch — remove and proceed.
            if destinationHasData {
                Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] destination has data without migrated flag; claiming new and preserving old for recovery")
                stateStore.markMigrated()
                pixelFiring.fire(.destinationConflict(label: label))
                ensureProtection(priorAttempts: state.protectionAttempts)
                return .proceed
            }
            Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] empty destination directory present; removing to clear path for move")
            do {
                try fileManager.removeItem(at: newURL)
            } catch {
                return handleMoveFailure(error, operation: .removingEmptyDestination, priorAttempts: state.attempts)
            }
        }

        do {
            try fileManager.createDirectory(at: newURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.moveItem(at: oldURL, to: newURL)
            Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] moved successfully")
            stateStore.markMigrated()
            pixelFiring.fire(.success(label: label))
            ensureProtection(priorAttempts: state.protectionAttempts)
            return .proceed
        } catch {
            return handleMoveFailure(error, operation: .move, priorAttempts: state.attempts)
        }
    }

    // MARK: - Static helpers

    static func defaultIsProtectedDataAvailable() -> Bool {
        UIApplication.shared.isProtectedDataAvailable
    }

    /// Creates `url` if needed and marks it `isExcludedFromBackup`. Fires
    /// `.excludeFromBackupFailed` on failure — silent inclusion of the
    /// encrypted DB in iCloud backups is what this guards against.
    static func excludeFromBackup(_ url: URL,
                                  label: DuckAiNativeStorageContainerMigrationLabel,
                                  pixelFiring: DuckAiNativeStorageContainerMigrationPixelFiring = NullDuckAiNativeStorageContainerMigrationPixelFiring(),
                                  fileManager: FileManager = .default) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            var url = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
        } catch {
            Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] failed to exclude \(url.lastPathComponent, privacy: .public) from backup: \(error.localizedDescription, privacy: .public)")
            pixelFiring.fire(.excludeFromBackupFailed(label: label, error: error))
        }
    }

    /// Recursively applies `completeUntilFirstUserAuthentication` to `url` and
    /// every child. Files moved from App Group keep their inherited
    /// `NSFileProtectionComplete` attribute, so without this the locked-device
    /// crash this migration exists to fix still happens. Setting it on the
    /// directory also fixes the default class new sidecars inherit.
    ///
    /// Returns the first error encountered, or `nil` on full success. A `nil`
    /// enumerator is reported as an error so the caller retries — otherwise
    /// we'd silently mark protection applied while children kept the wrong class.
    @discardableResult
    static func applyDefaultFileProtection(at url: URL, fileManager: FileManager = .default) -> Error? {
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        var firstError: Error?

        func apply(to path: String) {
            do {
                try fileManager.setAttributes(attributes, ofItemAtPath: path)
            } catch {
                Self.logger.error("[NativeStorage] failed to set file protection on \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                if firstError == nil { firstError = error }
            }
        }

        apply(to: url.path)

        let enumerator = fileManager.enumerator(at: url,
                                                includingPropertiesForKeys: nil,
                                                options: [],
                                                errorHandler: { childURL, error in
            Self.logger.error("[NativeStorage] enumerator error at \(childURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if firstError == nil { firstError = error }
            return true
        })
        guard let enumerator else {
            return firstError ?? NSError(domain: "DuckAiNativeStorageContainerMigration",
                                          code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Could not enumerate \(url.path)"])
        }
        for case let childURL as URL in enumerator {
            apply(to: childURL.path)
        }
        return firstError
    }

    /// Fire-mode stores DBs in `<UUID>/chats.db` subdirectories rather than at
    /// the root, so any non-empty `newURL` implies data that must not be wiped.
    private var destinationHasData: Bool {
        guard let children = try? fileManager.contentsOfDirectory(atPath: newURL.path) else {
            return false
        }
        return !children.isEmpty
    }

    private func resetExhaustedAttemptsIfNeeded(_ state: inout MigrationStateStore.State) {
        guard !state.isMigrated, state.attempts >= maxAttempts else { return }
        Self.logger.info("[NativeStorage] [\(label.rawValue, privacy: .public)] prior launch exhausted retry budget; resetting attempts")
        stateStore.resetCounters()
        state.attempts = 0
        state.protectionAttempts = 0
    }

    private func ensureProtection(priorAttempts: Int) {
        guard priorAttempts < maxAttempts else { return }
        guard fileManager.fileExists(atPath: newURL.path) else {
            // Nothing at the destination yet — no protection to enforce.
            stateStore.setProtectionAttempts(maxAttempts)
            return
        }

        protectionDispatcher {
            if let error = Self.applyDefaultFileProtection(at: newURL, fileManager: fileManager) {
                stateStore.setProtectionAttempts(priorAttempts + 1)
                pixelFiring.fire(.protectionFailed(label: label, error: error))
            } else {
                stateStore.setProtectionAttempts(maxAttempts)
            }
        }
    }

    private func handleMoveFailure(_ error: Error,
                                   operation: FailingOperation,
                                   priorAttempts: Int) -> DuckAiNativeStorageContainerMigrationOutcome {
        let attempt = priorAttempts + 1
        stateStore.setAttempts(attempt)
        if attempt >= maxAttempts {
            Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] \(operation.rawValue, privacy: .public) failed (attempt \(attempt)/\(maxAttempts)); giving up: \(error.localizedDescription, privacy: .public)")
            pixelFiring.fire(.gaveUp(label: label, error: error))
            return .skip
        }
        Self.logger.error("[NativeStorage] [\(label.rawValue, privacy: .public)] \(operation.rawValue, privacy: .public) failed (attempt \(attempt)/\(maxAttempts)); will retry next launch: \(error.localizedDescription, privacy: .public)")
        pixelFiring.fire(.attemptFailed(label: label, error: error))
        return .skip
    }

    private enum FailingOperation: String {
        case move
        case removingEmptyDestination
    }
}

/// Identifies the container being migrated. Raw value is suffixed onto pixel names.
enum DuckAiNativeStorageContainerMigrationLabel: String {
    case `default`
    case fireMode = "fire-mode"
}

/// Outcomes for the container relocation. Distinct from the JS→native chat-data
/// migration pixels (`duckAiNativeStorageMigration*`).
enum DuckAiNativeStorageContainerMigrationEvent {
    case notNeeded(label: DuckAiNativeStorageContainerMigrationLabel)
    case success(label: DuckAiNativeStorageContainerMigrationLabel)
    case attemptFailed(label: DuckAiNativeStorageContainerMigrationLabel, error: Error)
    case gaveUp(label: DuckAiNativeStorageContainerMigrationLabel, error: Error?)
    case protectionFailed(label: DuckAiNativeStorageContainerMigrationLabel, error: Error)
    case destinationConflict(label: DuckAiNativeStorageContainerMigrationLabel)
    case excludeFromBackupFailed(label: DuckAiNativeStorageContainerMigrationLabel, error: Error)
    case protectedDataUnavailable(label: DuckAiNativeStorageContainerMigrationLabel)
    case keyValueStoreReadFailed(label: DuckAiNativeStorageContainerMigrationLabel, error: Error)
}

enum DuckAiNativeStorageContainerMigrationOutcome {
    case proceed
    case skip
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
        case .success(let label):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationSuccess(label: label.rawValue))
        case .attemptFailed(let label, let error):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationAttemptFailed(label: label.rawValue), error: error)
        case .gaveUp(let label, let error):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationGaveUp(label: label.rawValue), error: error)
        case .protectionFailed(let label, let error):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationProtectionFailed(label: label.rawValue), error: error)
        case .destinationConflict(let label):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationDestinationConflict(label: label.rawValue))
        case .excludeFromBackupFailed(let label, let error):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationExcludeFromBackupFailed(label: label.rawValue), error: error)
        case .protectedDataUnavailable(let label):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationProtectedDataUnavailable(label: label.rawValue))
        case .keyValueStoreReadFailed(let label, let error):
            Pixel.fire(pixel: .duckAiNativeStorageContainerMigrationKeyValueStoreReadFailed(label: label.rawValue), error: error)
        }
    }
}

/// Runs the one-time move of a Duck.ai container from the shared App Group into
/// the app's Application Support directory.
protocol DuckAiNativeStorageContainerMigrating {
    @discardableResult
    func run() -> DuckAiNativeStorageContainerMigrationOutcome
}

private struct MigrationStateStore {

    struct State {
        let isMigrated: Bool
        var attempts: Int
        var protectionAttempts: Int
    }

    /// Tags errors that originate from a kv-store read so the migration's
    /// catch can distinguish them from any other propagating throw.
    struct ReadError: Error {
        let underlying: Error
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let migratedKey: String
    private let attemptsKey: String
    private let protectionAttemptsKey: String

    init(keyValueStore: ThrowingKeyValueStoring, migrationKey: String) {
        self.keyValueStore = keyValueStore
        self.migratedKey = migrationKey + ".migrated"
        self.attemptsKey = migrationKey + ".attempts"
        self.protectionAttemptsKey = migrationKey + ".protectionAttempts"
    }

    func load() throws -> State {
        do {
            return State(
                isMigrated: try keyValueStore.object(forKey: migratedKey) as? Bool ?? false,
                attempts: try keyValueStore.object(forKey: attemptsKey) as? Int ?? 0,
                protectionAttempts: try keyValueStore.object(forKey: protectionAttemptsKey) as? Int ?? 0
            )
        } catch {
            throw ReadError(underlying: error)
        }
    }

    func markMigrated() {
        try? keyValueStore.set(true, forKey: migratedKey)
        try? keyValueStore.removeObject(forKey: attemptsKey)
    }

    func setAttempts(_ value: Int) {
        try? keyValueStore.set(value, forKey: attemptsKey)
    }

    func setProtectionAttempts(_ value: Int) {
        try? keyValueStore.set(value, forKey: protectionAttemptsKey)
    }

    /// Clears `attempts` and `protectionAttempts`. Used when the prior launch
    /// exhausted the retry budget so this launch starts with a fresh budget.
    func resetCounters() {
        try? keyValueStore.removeObject(forKey: attemptsKey)
        try? keyValueStore.removeObject(forKey: protectionAttemptsKey)
    }
}
