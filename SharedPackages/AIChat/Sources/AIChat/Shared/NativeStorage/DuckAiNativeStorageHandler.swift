//
//  DuckAiNativeStorageHandler.swift
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

import DuckAiDataStore
import Foundation
import os.log
import Persistence

/// Public entry point for Duck.ai native storage. Pick a backing in `Mode`:
///
/// - `.disk(path:)` for persistent on-disk storage (encrypted SQLCipher DB + filesystem)
/// - `.memory` for transient in-memory storage (fire-mode contexts)
///
/// Both backings conform to `DuckAiNativeStorageHandling` and are interchangeable from
/// the caller's point of view; this class forwards every protocol call to the chosen
/// implementation.
public final class DuckAiNativeStorageHandler: DuckAiNativeStorageHandling {

    /// Default subdirectory name for the on-disk store. Callers compose this with the
    /// platform-appropriate base location (group container on iOS, application support on macOS).
    public static let defaultDirectoryName = "DuckAiNativeStorage"

    /// Entry keys (T&C / voice-mode consent) that survive across modes. Both `.disk` and
    /// `.memory` cases will copy these from `seedSource` on init when present and missing
    /// from the destination, so a user who has accepted Duck.ai T&C / voice-mode consent
    /// in normal mode isn't re-prompted in a fire context.
    public static let consentSeededEntryKeys: Set<String> = [
        "duckaiHasAgreedToTerms",
        "hasVoiceModeConsent"
    ]

    public enum Mode {
        /// On-disk storage at `path`. The directory is created if it doesn't exist.
        /// When `seedSource` is provided, consent keys (see `consentSeededEntryKeys`) are
        /// copied from it into this store on init if not already present here.
        case disk(path: URL,
                  keyStoreProvider: DuckAiKeyStoreProvider,
                  pixelFiring: DuckAiNativeStoragePixelFiring = NullDuckAiNativeStoragePixelFiring(),
                  seedSource: DuckAiNativeStorageHandling? = nil)
        /// In-memory storage. `seedSource`, when provided, is read once at init time to
        /// copy consent keys (see `consentSeededEntryKeys`).
        case memory(seedSource: DuckAiNativeStorageHandling? = nil)
    }

    private let backing: DuckAiNativeStorageHandling

    public init(_ mode: Mode) throws {
        switch mode {
        case .disk(let path, let keyStoreProvider, let pixelFiring, let seedSource):
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)

                let encryptionKey = try keyStoreProvider.getOrCreateKey()
                let settingsStore = try KeyValueFileStore(location: path, name: "settings.plist")
                let dataStore = try DuckAiNativeDataStore(
                    databaseURL: path.appendingPathComponent("chats.db"),
                    filesDirectoryURL: path.appendingPathComponent("files"),
                    key: encryptionKey
                )
                let handler = DuckAiNativeDiskStorageHandler(
                    settingsStore: settingsStore.throwingKeyedStoring(),
                    dataStore: dataStore
                )
                Self.seedConsentEntries(into: handler, from: seedSource)
                self.backing = handler
                Logger.aiChat.debug("DuckAiNativeStorageHandler: disk store initialized at \(path.path)")
                pixelFiring.fire(.initSuccess)
            } catch {
                pixelFiring.fire(.initError(error))
                throw error
            }

        case .memory(let seedSource):
            self.backing = DuckAiNativeMemoryStorageHandler(seedSource: seedSource)
        }
    }

    /// Copies `consentSeededEntryKeys` from `source` into `target` for any keys missing
    /// from `target`. No-op when `source` is `nil`.
    public static func seedConsentEntries(into target: DuckAiNativeStorageHandling,
                                          from source: DuckAiNativeStorageHandling?) {
        guard let source else { return }
        for key in consentSeededEntryKeys {
            if (try? target.getEntry(key: key)) == nil,
               let value = try? source.getEntry(key: key) {
                try? target.putEntry(key: key, value: value)
            }
        }
    }

    // MARK: - DuckAiNativeStorageHandling forwarding

    public func putEntry(key: String, value: Any) throws { try backing.putEntry(key: key, value: value) }
    public func getEntry(key: String) throws -> Any? { try backing.getEntry(key: key) }
    public func getAllEntries() throws -> [String: Any] { try backing.getAllEntries() }
    public func deleteEntry(key: String) throws { try backing.deleteEntry(key: key) }
    public func deleteAllEntries() throws { try backing.deleteAllEntries() }
    public func replaceAllEntries(_ entries: [String: Any]) throws { try backing.replaceAllEntries(entries) }

    public func putChat(chatId: String, data: Data) throws { try backing.putChat(chatId: chatId, data: data) }
    public func putChats(_ chats: [DuckAiChatRecord]) throws { try backing.putChats(chats) }
    public func getChat(chatId: String) throws -> DuckAiChatRecord? { try backing.getChat(chatId: chatId) }
    public func getAllChats() throws -> [DuckAiChatRecord] { try backing.getAllChats() }
    public func deleteChat(chatId: String) throws { try backing.deleteChat(chatId: chatId) }
    public func deleteAllChats() throws { try backing.deleteAllChats() }

    public func putFile(uuid: String, chatId: String, data: Data) throws { try backing.putFile(uuid: uuid, chatId: chatId, data: data) }
    public func getFile(uuid: String) throws -> DuckAiFileContent? { try backing.getFile(uuid: uuid) }
    public func listFiles() throws -> [DuckAiFileMetadata] { try backing.listFiles() }
    public func deleteFile(uuid: String) throws { try backing.deleteFile(uuid: uuid) }
    public func deleteFiles(chatId: String) throws { try backing.deleteFiles(chatId: chatId) }
    public func deleteAllFiles() throws { try backing.deleteAllFiles() }

    public func isMigrationDone() throws -> Bool { try backing.isMigrationDone() }
    public func isMigrationDone(key: String) throws -> Bool { try backing.isMigrationDone(key: key) }
    public func markMigrationDone(key: String) throws { try backing.markMigrationDone(key: key) }
}
