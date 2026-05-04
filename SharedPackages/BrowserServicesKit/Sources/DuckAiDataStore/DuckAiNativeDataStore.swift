//
//  DuckAiNativeDataStore.swift
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

import Common
import CryptoKit
import Foundation
import GRDB
import os.log

public final class DuckAiNativeDataStore: DuckAiNativeDataStoring {

    private let dbQueue: DatabaseQueue
    private let filesDirectoryURL: URL
    private let encryptionKey: SymmetricKey

    /// Creates an encrypted data store backed by SQLCipher.
    ///
    /// If an existing unencrypted database is found, it is deleted and recreated
    /// as an encrypted database. This handles the migration from the pre-encryption
    /// storage format.
    ///
    /// - Parameters:
    ///   - databaseURL: Path to the SQLite database file.
    ///   - filesDirectoryURL: Directory for storing file attachments on disk.
    ///   - key: 256-bit symmetric key used for SQLCipher encryption.
    public init(databaseURL: URL, filesDirectoryURL: URL, key: Data) throws {
        self.filesDirectoryURL = filesDirectoryURL
        self.encryptionKey = SymmetricKey(data: key)

        let fileManager = FileManager.default
        let dbDirectory = databaseURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: filesDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw DuckAiNativeDataStoreError.directoryCreationFailed(error)
        }

        do {
            dbQueue = try Self.openDatabase(at: databaseURL, key: key, filesDirectoryURL: filesDirectoryURL)
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }

        try Self.runMigrations(on: dbQueue)
    }

    /// Opens an encrypted database, recreating it if the existing file is unencrypted or corrupt.
    /// When recreating, also removes orphaned files from `filesDirectoryURL` to ensure
    /// no plaintext data persists on disk.
    private static func openDatabase(at url: URL, key: Data, filesDirectoryURL: URL) throws -> DatabaseQueue {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.usePassphrase(key)
        }

        do {
            return try DatabaseQueue(path: url.path, configuration: config)
        } catch let error as DatabaseError where [.SQLITE_NOTADB, .SQLITE_CORRUPT].contains(error.resultCode) {
            Logger.nativeStorageDebug.warning("[NativeStorage] Existing database is unencrypted or corrupt, recreating: \(error.resultCode)")
            try? FileManager.default.removeItem(at: url)
            Self.removeOrphanedFiles(in: filesDirectoryURL)
            return try DatabaseQueue(path: url.path, configuration: config)
        }
    }

    private static func removeOrphanedFiles(in directory: URL) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Migrations

    private static func runMigrations(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "duck_ai_chats") { t in
                t.primaryKey("chatId", .text).notNull()
                t.column("data", .blob).notNull()
            }

            try db.create(table: "duck_ai_files") { t in
                t.primaryKey("uuid", .text).notNull()
                t.column("chatId", .text).notNull()
                t.column("dataSize", .integer).notNull()
                t.column("filePath", .text).notNull()
            }
        }

        do {
            try migrator.migrate(dbQueue)
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    // MARK: - Chat Records

    private struct ChatRecord: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "duck_ai_chats"
        let chatId: String
        let data: Data
    }

    // MARK: - File Records

    private struct FileRecord: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "duck_ai_files"
        let uuid: String
        let chatId: String
        let dataSize: Int
        let filePath: String
    }

    // MARK: - Chats

    public func putChat(chatId: String, data: Data) throws {
        let record = ChatRecord(chatId: chatId, data: data)
        do {
            try dbQueue.write { db in
                try record.save(db)
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func putChats(_ chats: [DuckAiChatRecord]) throws {
        do {
            try dbQueue.write { db in
                for chat in chats where !chat.chatId.isEmpty {
                    let record = ChatRecord(chatId: chat.chatId, data: chat.data)
                    try record.save(db)
                }
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func getChat(chatId: String) throws -> DuckAiChatRecord? {
        do {
            return try dbQueue.read { db in
                guard let record = try ChatRecord.fetchOne(db, key: chatId) else { return nil }
                return DuckAiChatRecord(chatId: record.chatId, data: record.data)
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func getAllChats() throws -> [DuckAiChatRecord] {
        do {
            return try dbQueue.read { db in
                let records = try ChatRecord.fetchAll(db)
                return records.map { DuckAiChatRecord(chatId: $0.chatId, data: $0.data) }
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteChat(chatId: String) throws {
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_chats WHERE chatId = ?", arguments: [chatId])
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteAllChats() throws {
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_chats")
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    // MARK: - Files (Implemented in Task 3)

    private func validatedFileUUID(for uuid: String) throws -> String {
        guard let parsed = UUID(uuidString: uuid) else {
            throw DuckAiNativeDataStoreError.invalidFileIdentifier
        }
        return parsed.uuidString
    }

    public func putFile(uuid: String, chatId: String, data: Data) throws {
        let normalizedUUID = try validatedFileUUID(for: uuid)
        let fileURL = filesDirectoryURL.appendingPathComponent(normalizedUUID)

        do {
            let sealed = try AES.GCM.seal(data, using: encryptionKey)
            guard let encrypted = sealed.combined else {
                throw DuckAiNativeDataStoreError.fileEncryptionError
            }
            try encrypted.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch let error as DuckAiNativeDataStoreError {
            throw error
        } catch {
            throw DuckAiNativeDataStoreError.fileWriteError(error)
        }

        let fileName = fileURL.lastPathComponent
        let record = FileRecord(uuid: normalizedUUID, chatId: chatId, dataSize: data.count, filePath: fileName)
        do {
            try dbQueue.write { db in
                try record.save(db)
            }
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        let normalizedUUID = try validatedFileUUID(for: uuid)
        let fileURL = filesDirectoryURL.appendingPathComponent(normalizedUUID)

        let record: FileRecord?
        do {
            record = try dbQueue.read { db in
                try FileRecord.fetchOne(db, key: normalizedUUID)
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }

        guard let record else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let encrypted = try Data(contentsOf: fileURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            let data = try AES.GCM.open(sealedBox, using: encryptionKey)
            return DuckAiFileContent(uuid: record.uuid, chatId: record.chatId, data: data)
        } catch {
            throw DuckAiNativeDataStoreError.fileReadError(error)
        }
    }

    public func listFiles() throws -> [DuckAiFileMetadata] {
        do {
            return try dbQueue.read { db in
                let records = try FileRecord.fetchAll(db)
                return records.map { DuckAiFileMetadata(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.dataSize) }
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteFile(uuid: String) throws {
        let normalizedUUID = try validatedFileUUID(for: uuid)
        let fileURL = filesDirectoryURL.appendingPathComponent(normalizedUUID)
        try? FileManager.default.removeItem(at: fileURL)

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_files WHERE uuid = ?", arguments: [normalizedUUID])
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteFiles(chatId: String) throws {
        let fileNames: [String]
        do {
            fileNames = try dbQueue.read { db in
                try FileRecord
                    .filter(Column("chatId") == chatId)
                    .fetchAll(db)
                    .map { $0.filePath }
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }

        for fileName in fileNames {
            let fileURL = filesDirectoryURL.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_files WHERE chatId = ?", arguments: [chatId])
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteAllFiles() throws {
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(at: filesDirectoryURL, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_files")
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }
}
