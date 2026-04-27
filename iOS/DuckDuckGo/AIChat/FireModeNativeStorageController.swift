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
import PrivacyConfig
/// Owns the iOS fire-mode Duck.ai native storage handler and rotates it on burn.
///
/// The underlying disk-backed handler lives at
/// `<group>/DuckAiNativeStorage-fireMode/<UUID>/`, where `<UUID>` is
/// `DataStoreIDManager.currentFireModeID` — matching the WebKit fire-mode data
/// store identity. On burn we invalidate the current ID, swap in a fresh handler at
/// the new ID's directory, and asynchronously delete the old directory on disk.
///
/// Conforms to `DuckAiNativeStorageHandling` so consumers don't need to know about
/// rotation; only `FireExecutor` calls `rotate()` directly on the concrete type.
final class FireModeNativeStorageController: DuckAiNativeStorageHandling {

    private enum Constants {
        static let fireModeDirectoryName = "DuckAiNativeStorage-fireMode"
    }

    private let lock = NSLock()
    private var inner: DuckAiNativeStorageHandling

    private let baseDirectoryURL: URL
    private let dataStoreIDManager: DataStoreIDManaging
    private let consentSeedSource: DuckAiNativeStorageHandling?
    private let pixelFiring: DuckAiNativeStoragePixelFiring
    private let keyStoreAccessGroup: String

    /// Returns `nil` if `aiChatNativeStorage` is off, the app group container is missing,
    /// or the underlying store can't be opened.
    init?(featureFlagger: FeatureFlagger,
          dataStoreIDManager: DataStoreIDManaging = DataStoreIDManager.shared,
          consentSeedSource: DuckAiNativeStorageHandling?,
          appConfigurationGroupName: String,
          pixelFiring: DuckAiNativeStoragePixelFiring = DuckAiNativeStoragePixelAdapter()) {
        guard featureFlagger.isFeatureOn(.aiChatNativeStorage),
              let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appConfigurationGroupName) else {
            return nil
        }
        self.baseDirectoryURL = groupContainer.appendingPathComponent(Constants.fireModeDirectoryName)
        self.dataStoreIDManager = dataStoreIDManager
        self.consentSeedSource = consentSeedSource
        self.pixelFiring = pixelFiring
        self.keyStoreAccessGroup = appConfigurationGroupName

        let id = dataStoreIDManager.currentFireModeID
        guard let handler = Self.makeHandler(in: baseDirectoryURL,
                                             id: id,
                                             keyStoreAccessGroup: appConfigurationGroupName,
                                             pixelFiring: pixelFiring,
                                             seedSource: consentSeedSource) else {
            return nil
        }
        self.inner = handler
        Self.cleanupPendingRemovalDirectories(in: baseDirectoryURL,
                                              dataStoreIDManager: dataStoreIDManager)
    }

    /// Invalidates the current fire-mode UUID, opens a fresh handler at the new UUID's
    /// directory, seeds consent, and asynchronously deletes the old directory.
    /// Falls back to clearing the existing store in place if opening a new one fails.
    func rotate() {
        lock.lock()
        defer { lock.unlock() }
        let oldID = dataStoreIDManager.currentFireModeID
        dataStoreIDManager.invalidateCurrentFireModeID()
        let newID = dataStoreIDManager.currentFireModeID
        guard let new = Self.makeHandler(in: baseDirectoryURL,
                                         id: newID,
                                         keyStoreAccessGroup: keyStoreAccessGroup,
                                         pixelFiring: pixelFiring,
                                         seedSource: consentSeedSource) else {
            Logger.aiChat.error("[NativeStorage] Failed to open fire-mode store at new ID \(newID); clearing in place instead")
            try? inner.deleteAllChats()
            try? inner.deleteAllFiles()
            try? inner.deleteAllEntries()
            DuckAiNativeStorageHandler.seedConsentEntries(into: inner, from: consentSeedSource)
            return
        }
        inner = new

        DispatchQueue.global(qos: .utility).async { [baseDirectoryURL, dataStoreIDManager] in
            let url = baseDirectoryURL.appendingPathComponent(oldID.uuidString)
            try? FileManager.default.removeItem(at: url)
            dataStoreIDManager.removePendingRemovalFireModeID(oldID)
        }
    }

    private var current: DuckAiNativeStorageHandling {
        lock.lock(); defer { lock.unlock() }
        return inner
    }

    // MARK: - Helpers

    private static func makeHandler(in baseDirectoryURL: URL,
                                    id: UUID,
                                    keyStoreAccessGroup: String,
                                    pixelFiring: DuckAiNativeStoragePixelFiring,
                                    seedSource: DuckAiNativeStorageHandling?) -> DuckAiNativeStorageHandling? {
        let containerURL = baseDirectoryURL.appendingPathComponent(id.uuidString)
        do {
            return try DuckAiNativeStorageHandler(
                .disk(path: containerURL,
                      keyStoreProvider: DuckAiKeyStoreProvider(accessGroup: keyStoreAccessGroup),
                      pixelFiring: pixelFiring,
                      seedSource: seedSource)
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

    func putEntry(key: String, value: Any) throws { try current.putEntry(key: key, value: value) }
    func getEntry(key: String) throws -> Any? { try current.getEntry(key: key) }
    func getAllEntries() throws -> [String: Any] { try current.getAllEntries() }
    func deleteEntry(key: String) throws { try current.deleteEntry(key: key) }
    func deleteAllEntries() throws { try current.deleteAllEntries() }
    func replaceAllEntries(_ entries: [String: Any]) throws { try current.replaceAllEntries(entries) }

    func putChat(chatId: String, data: Data) throws { try current.putChat(chatId: chatId, data: data) }
    func putChats(_ chats: [DuckAiChatRecord]) throws { try current.putChats(chats) }
    func getChat(chatId: String) throws -> DuckAiChatRecord? { try current.getChat(chatId: chatId) }
    func getAllChats() throws -> [DuckAiChatRecord] { try current.getAllChats() }
    func deleteChat(chatId: String) throws { try current.deleteChat(chatId: chatId) }
    func deleteAllChats() throws { try current.deleteAllChats() }

    func putFile(uuid: String, chatId: String, data: Data) throws { try current.putFile(uuid: uuid, chatId: chatId, data: data) }
    func getFile(uuid: String) throws -> DuckAiFileContent? { try current.getFile(uuid: uuid) }
    func listFiles() throws -> [DuckAiFileMetadata] { try current.listFiles() }
    func deleteFile(uuid: String) throws { try current.deleteFile(uuid: uuid) }
    func deleteFiles(chatId: String) throws { try current.deleteFiles(chatId: chatId) }
    func deleteAllFiles() throws { try current.deleteAllFiles() }

    func isMigrationDone() throws -> Bool { try current.isMigrationDone() }
    func isMigrationDone(key: String) throws -> Bool { try current.isMigrationDone(key: key) }
    func markMigrationDone(key: String) throws { try current.markMigrationDone(key: key) }
}
