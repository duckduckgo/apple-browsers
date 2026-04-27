//
//  DuckAiNativeMemoryStorageHandler.swift
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
import DuckAiDataStore

/// In-memory `DuckAiNativeStorageHandling` for fire-mode contexts.
///
/// All chats, files, entries, and migration markers live for the lifetime
/// of the instance only. Releasing the instance — or closing the fire window
/// that owns it — discards the data with no on-disk residue.
///
/// `seedSource`, when provided, is consulted on every read for the small allow-list of
/// consent keys (see `DuckAiNativeStorageConsent.entryKeys`). When the in-memory entries
/// dictionary doesn't have one of those keys, `getEntry` / `getAllEntries` read it through
/// to `seedSource`. Writes always go to the in-memory dictionary only — the seed source is
/// never modified — so a user who has accepted Duck.ai T&C / voice-mode consent in normal
/// mode isn't re-prompted in fire mode, even after the FE calls `replaceAllEntries`.
public final class DuckAiNativeMemoryStorageHandler: DuckAiNativeStorageHandling {

    private let lock = NSLock()
    private var entries: [String: Any] = [:]
    private var chats: [String: Data] = [:]
    private var files: [String: DuckAiFileContent] = [:]
    private var migrations: [String: Bool] = [:]
    private let seedSource: DuckAiNativeStorageHandling?

    public init(seedSource: DuckAiNativeStorageHandling? = nil) {
        self.seedSource = seedSource
    }

    // MARK: - Entries

    public func putEntry(key: String, value: Any) throws {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = value
    }

    public func getEntry(key: String) throws -> Any? {
        lock.lock()
        if let value = entries[key] {
            lock.unlock()
            return value
        }
        lock.unlock()
        guard let seedSource, DuckAiNativeStorageConsent.entryKeys.contains(key) else { return nil }
        return try? seedSource.getEntry(key: key)
    }

    public func getAllEntries() throws -> [String: Any] {
        lock.lock()
        var result = entries
        lock.unlock()
        guard let seedSource else { return result }
        for key in DuckAiNativeStorageConsent.entryKeys where result[key] == nil {
            if let value = try? seedSource.getEntry(key: key) {
                result[key] = value
            }
        }
        return result
    }

    public func deleteEntry(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    public func deleteAllEntries() throws {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    public func replaceAllEntries(_ entries: [String: Any]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.entries = entries
    }

    // MARK: - Chats

    public func putChat(chatId: String, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        chats[chatId] = data
    }

    public func putChats(_ chats: [DuckAiChatRecord]) throws {
        lock.lock()
        defer { lock.unlock() }
        for chat in chats where !chat.chatId.isEmpty {
            self.chats[chat.chatId] = chat.data
        }
    }

    public func getChat(chatId: String) throws -> DuckAiChatRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = chats[chatId] else { return nil }
        return DuckAiChatRecord(chatId: chatId, data: data)
    }

    public func getAllChats() throws -> [DuckAiChatRecord] {
        lock.lock()
        defer { lock.unlock() }
        return chats.map { DuckAiChatRecord(chatId: $0.key, data: $0.value) }
    }

    public func deleteChat(chatId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        chats.removeValue(forKey: chatId)
    }

    public func deleteAllChats() throws {
        lock.lock()
        defer { lock.unlock() }
        chats.removeAll()
    }

    // MARK: - Files

    public func putFile(uuid: String, chatId: String, data: Data) throws {
        guard let normalized = UUID(uuidString: uuid)?.uuidString else {
            throw DuckAiNativeDataStoreError.invalidFileIdentifier
        }
        lock.lock()
        defer { lock.unlock() }
        files[normalized] = DuckAiFileContent(uuid: normalized, chatId: chatId, data: data)
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        guard let normalized = UUID(uuidString: uuid)?.uuidString else {
            throw DuckAiNativeDataStoreError.invalidFileIdentifier
        }
        lock.lock()
        defer { lock.unlock() }
        return files[normalized]
    }

    public func listFiles() throws -> [DuckAiFileMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return files.values.map { DuckAiFileMetadata(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.data.count) }
    }

    public func deleteFile(uuid: String) throws {
        guard let normalized = UUID(uuidString: uuid)?.uuidString else {
            throw DuckAiNativeDataStoreError.invalidFileIdentifier
        }
        lock.lock()
        defer { lock.unlock() }
        files.removeValue(forKey: normalized)
    }

    public func deleteFiles(chatId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        for (uuid, file) in files where file.chatId == chatId {
            files.removeValue(forKey: uuid)
        }
    }

    public func deleteAllFiles() throws {
        lock.lock()
        defer { lock.unlock() }
        files.removeAll()
    }

    // MARK: - Migration

    public func isMigrationDone() throws -> Bool {
        try DuckAiMigrationKey.allKeys.allSatisfy { try isMigrationDone(key: $0) }
    }

    public func isMigrationDone(key: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return migrations[key] ?? false
    }

    public func markMigrationDone(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        migrations[key] = true
    }
}
