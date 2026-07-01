//
//  FireModeNativeStorageController.swift
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

import AIChat
import BrowserServicesKit
import Core
import DuckAiDataStore
import Foundation
import os.log
import Persistence
import PrivacyConfig
/// Owns the iOS fire-mode Duck.ai native storage handler and rotates it on burn.
///
/// The underlying disk-backed handler lives at
/// `<Application Support>/DuckAiNativeStorage-fireMode/<UUID>/`, where `<UUID>` is
/// `DataStoreIDManager.currentFireModeID` — matching the WebKit fire-mode data
/// store identity. On burn we invalidate the current ID, swap in a fresh handler at
/// the new ID's directory, and asynchronously delete the old directory on disk.
///
/// On first launch after upgrading from a build that stored fire-mode data in the
/// shared app-group container, the existing directory is moved into Application
/// Support; see `DuckAiNativeStorageContainerMigration`.
///
/// Conforms to `DuckAiNativeStorageHandling` so consumers don't need to know about
/// rotation; only `FireExecutor` calls `syncWithCurrentFireModeID()` directly on the concrete type.
final class FireModeNativeStorageController: DuckAiNativeStorageHandling {

    private enum Constants {
        static let fireModeDirectoryName = "DuckAiNativeStorage-fireMode"
    }

    private let lock = NSLock()
    private var _inner: DuckAiNativeStorageHandling
    private var inner: DuckAiNativeStorageHandling {
        get {
            lock.lock(); defer { lock.unlock() }
            return _inner
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _inner = newValue
        }
    }
    private var openedID: UUID

    private let baseDirectoryURL: URL
    private let dataStoreIDManager: DataStoreIDManaging
    private let consentSeedSource: DuckAiNativeStorageHandling?
    private let pixelFiring: DuckAiNativeStoragePixelFiring
    private let keyStoreAccessGroup: String

    /// Returns `nil` if `aiChatNativeStorage` is off, the required container is
    /// unavailable, or the underlying store can't be opened.
    init?(featureFlagger: FeatureFlagger,
          dataStoreIDManager: DataStoreIDManaging = DataStoreIDManager.shared,
          consentSeedSource: DuckAiNativeStorageHandling?,
          appConfigurationGroupName: String,
          keyValueStore: ThrowingKeyValueStoring,
          pixelFiring: DuckAiNativeStoragePixelFiring = DuckAiNativeStoragePixelAdapter()) {
        guard featureFlagger.isFeatureOn(.aiChatNativeStorage) else { return nil }

        let baseDirectoryURL: URL
        if featureFlagger.isFeatureOn(.duckAINativeStoragePathMigration) {
            guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            baseDirectoryURL = appSupportURL.appendingPathComponent(Constants.fireModeDirectoryName)

            if let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appConfigurationGroupName) {
                let outcome = DuckAiNativeStorageContainerMigration(
                    oldURL: groupContainer.appendingPathComponent(Constants.fireModeDirectoryName),
                    newURL: baseDirectoryURL,
                    migrationKey: "com.duckduckgo.duckai.nativeStorage.fireModeMigratedFromAppGroup",
                    label: .fireMode,
                    keyValueStore: keyValueStore,
                    pixelFiring: DuckAiNativeStorageContainerMigrationPixelAdapter(),
                    lockedLaunchFixEnabled: featureFlagger.isFeatureOn(.duckAINativeStorageMigrationLockedLaunchFix)
                ).run()
                if outcome == .skip {
                    return nil
                }
            }

            DuckAiNativeStorageContainerMigration.excludeFromBackup(baseDirectoryURL,
                                                                    label: .fireMode,
                                                                    pixelFiring: DuckAiNativeStorageContainerMigrationPixelAdapter())
        } else {
            // Path migration disabled: keep the legacy App Group container.
            guard let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appConfigurationGroupName) else {
                return nil
            }
            baseDirectoryURL = groupContainer.appendingPathComponent(Constants.fireModeDirectoryName)
        }

        self.baseDirectoryURL = baseDirectoryURL
        self.dataStoreIDManager = dataStoreIDManager
        self.consentSeedSource = consentSeedSource
        self.pixelFiring = pixelFiring
        self.keyStoreAccessGroup = appConfigurationGroupName

        let id = dataStoreIDManager.currentFireModeID
        guard let handler = Self.makeHandler(in: baseDirectoryURL,
                                             id: id,
                                             keyStoreAccessGroup: appConfigurationGroupName,
                                             pixelFiring: pixelFiring) else {
            return nil
        }
        self._inner = handler
        self.openedID = id
        Self.cleanupPendingRemovalDirectories(in: baseDirectoryURL,
                                              dataStoreIDManager: dataStoreIDManager)
    }

    /// Reopens the inner handler at `DataStoreIDManager.currentFireModeID`'s directory if
    /// the ID has changed since the last call. Idempotent — no-op when the ID hasn't moved.
    ///
    /// The fire-mode UUID is rotated by `WebsiteDataFireWorker` as part of a `.data` burn.
    /// Call this after the burn completes so the native store follows the WK store rather
    /// than initiating its own rotation (which would advance the ID twice).
    /// Falls back to clearing the existing store in place if opening a new one fails.
    func syncWithCurrentFireModeID() {
        lock.lock()
        defer { lock.unlock() }
        let currentID = dataStoreIDManager.currentFireModeID
        guard currentID != openedID else { return }
        let previousID = openedID
        guard let new = Self.makeHandler(in: baseDirectoryURL,
                                         id: currentID,
                                         keyStoreAccessGroup: keyStoreAccessGroup,
                                         pixelFiring: pixelFiring) else {
            Logger.aiChat.error("[NativeStorage] Failed to open fire-mode store at id \(currentID); clearing in place instead")
            try? _inner.deleteAllChats()
            try? _inner.deleteAllFiles()
            try? _inner.deleteAllEntries()
            return
        }
        _inner = new
        openedID = currentID

        DispatchQueue.global(qos: .utility).async { [baseDirectoryURL, dataStoreIDManager] in
            let url = baseDirectoryURL.appendingPathComponent(previousID.uuidString)
            try? FileManager.default.removeItem(at: url)
            dataStoreIDManager.removePendingRemovalFireModeID(previousID)
        }
    }

    // MARK: - Helpers

    private static func makeHandler(in baseDirectoryURL: URL,
                                    id: UUID,
                                    keyStoreAccessGroup: String,
                                    pixelFiring: DuckAiNativeStoragePixelFiring) -> DuckAiNativeStorageHandling? {
        let containerURL = baseDirectoryURL.appendingPathComponent(id.uuidString)
        let dbURL = containerURL.appendingPathComponent("chats.db")
        if !FileManager.default.fileExists(atPath: dbURL.path) {
            Logger.aiChat.info("[NativeStorage] fire-mode DB does not exist yet for id \(id), will be created at: \(dbURL.path)")
        }
        do {
            return try DuckAiNativeStorageHandler(
                .disk(path: containerURL,
                      keyStoreProvider: DuckAiKeyStoreProvider(accessGroup: keyStoreAccessGroup),
                      pixelFiring: pixelFiring)
            )
        } catch {
            Logger.aiChat.error("[NativeStorage] fire-mode handler init failed for id \(id): \(error)")
            return nil
        }
    }

    private static func cleanupPendingRemovalDirectories(in baseURL: URL,
                                                         dataStoreIDManager: DataStoreIDManaging) {
        let pending = dataStoreIDManager.pendingRemovalFireModeIDs
        guard !pending.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            for id in pending {
                let url = baseURL.appendingPathComponent(id.uuidString)
                try? fileManager.removeItem(at: url)
                dataStoreIDManager.removePendingRemovalFireModeID(id)
            }
        }
    }

    // MARK: - DuckAiNativeStorageHandling forwarding

    func putEntry(key: String, value: Any) throws { try inner.putEntry(key: key, value: value) }

    /// Reads through to `consentSeedSource` for the small consent allow-list when the
    /// fire-mode store doesn't have the key — keeps the user from being re-prompted
    /// after `replaceAllEntries` or a fresh fire-mode UUID rotation.
    func getEntry(key: String) throws -> Any? {
        if let value = try inner.getEntry(key: key) { return value }
        guard let consentSeedSource,
              DuckAiNativeStorageConsent.entryKeys.contains(key) else {
            return nil
        }
        return try? consentSeedSource.getEntry(key: key)
    }

    func getAllEntries() throws -> [String: Any] {
        var entries = try inner.getAllEntries()
        guard let consentSeedSource else { return entries }
        for key in DuckAiNativeStorageConsent.entryKeys where entries[key] == nil {
            if let value = try? consentSeedSource.getEntry(key: key) {
                entries[key] = value
            }
        }
        return entries
    }

    func deleteEntry(key: String) throws { try inner.deleteEntry(key: key) }
    func deleteAllEntries() throws { try inner.deleteAllEntries() }
    func replaceAllEntries(_ entries: [String: Any]) throws { try inner.replaceAllEntries(entries) }

    func putChat(chatId: String, data: Data) throws { try inner.putChat(chatId: chatId, data: data) }
    func putChats(_ chats: [DuckAiChatRecord]) throws { try inner.putChats(chats) }
    func getChat(chatId: String) throws -> DuckAiChatRecord? { try inner.getChat(chatId: chatId) }
    func getAllChats() throws -> [DuckAiChatRecord] { try inner.getAllChats() }
    func deleteChat(chatId: String) throws { try inner.deleteChat(chatId: chatId) }
    func deleteAllChats() throws { try inner.deleteAllChats() }

    func putFile(uuid: String, chatId: String, data: Data) throws { try inner.putFile(uuid: uuid, chatId: chatId, data: data) }
    func getFile(uuid: String) throws -> DuckAiFileContent? { try inner.getFile(uuid: uuid) }
    func listFiles() throws -> [DuckAiFileMetadata] { try inner.listFiles() }
    func deleteFile(uuid: String) throws { try inner.deleteFile(uuid: uuid) }
    func deleteFiles(chatId: String) throws { try inner.deleteFiles(chatId: chatId) }
    func deleteAllFiles() throws { try inner.deleteAllFiles() }

    func isMigrationDone() throws -> Bool { try inner.isMigrationDone() }
    func isMigrationDone(key: String) throws -> Bool { try inner.isMigrationDone(key: key) }
    func markMigrationDone(key: String) throws { try inner.markMigrationDone(key: key) }

    var setupSucceeded: Bool? { inner.setupSucceeded }
}
