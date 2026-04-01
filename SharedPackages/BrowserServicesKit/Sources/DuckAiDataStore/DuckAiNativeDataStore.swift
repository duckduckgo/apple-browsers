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

import Foundation
import GRDB
import os.log

public final class DuckAiNativeDataStore: DuckAiNativeDataStoring {

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "DuckAiNativeDataStore")

    private let dbQueue: DatabaseQueue
    private let filesDirectoryURL: URL

    public init(databaseURL: URL, filesDirectoryURL: URL) throws {
        self.filesDirectoryURL = filesDirectoryURL

        let fileManager = FileManager.default
        let dbDirectory = databaseURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: filesDirectoryURL, withIntermediateDirectories: true)
        } catch {
            Self.log.error("DuckAiNativeDataStore: Failed to create directories: \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.directoryCreationFailed(error)
        }

        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        } catch {
            Self.log.error("DuckAiNativeDataStore: Failed to open database at \(databaseURL.path): \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }

        try Self.runMigrations(on: dbQueue)
        Self.log.debug("DuckAiNativeDataStore: Initialized at \(databaseURL.path)")
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
        Self.log.debug("DuckAiNativeDataStore: putChat \(chatId) (\(data.count) bytes)")
        let record = ChatRecord(chatId: chatId, data: data)
        do {
            try dbQueue.write { db in
                try record.save(db)
            }
        } catch {
            Self.log.error("DuckAiNativeDataStore: putChat failed for \(chatId): \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func getAllChats() throws -> [DuckAiChatRecord] {
        do {
            let result = try dbQueue.read { db in
                let records = try ChatRecord.fetchAll(db)
                return records.map { DuckAiChatRecord(chatId: $0.chatId, data: $0.data) }
            }
            Self.log.debug("DuckAiNativeDataStore: getAllChats returned \(result.count) chats")
            return result
        } catch {
            Self.log.error("DuckAiNativeDataStore: getAllChats failed: \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteChat(chatId: String) throws {
        Self.log.debug("DuckAiNativeDataStore: deleteChat \(chatId)")
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_chats WHERE chatId = ?", arguments: [chatId])
            }
        } catch {
            Self.log.error("DuckAiNativeDataStore: deleteChat failed for \(chatId): \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteAllChats() throws {
        Self.log.debug("DuckAiNativeDataStore: deleteAllChats")
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_chats")
            }
        } catch {
            Self.log.error("DuckAiNativeDataStore: deleteAllChats failed: \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    // MARK: - Files (Implemented in Task 3)

    public func putFile(uuid: String, chatId: String, data: Data) throws {
        Self.log.debug("DuckAiNativeDataStore: putFile \(uuid) for chat \(chatId) (\(data.count) bytes)")
        let fileURL = filesDirectoryURL.appendingPathComponent(uuid)

        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.log.error("DuckAiNativeDataStore: putFile disk write failed for \(uuid): \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.fileWriteError(error)
        }

        let record = FileRecord(uuid: uuid, chatId: chatId, dataSize: data.count, filePath: uuid)
        do {
            try dbQueue.write { db in
                try record.save(db)
            }
        } catch {
            Self.log.error("DuckAiNativeDataStore: putFile DB write failed for \(uuid), cleaning up file: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: fileURL)
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        let record: FileRecord?
        do {
            record = try dbQueue.read { db in
                try FileRecord.fetchOne(db, key: uuid)
            }
        } catch {
            Self.log.error("DuckAiNativeDataStore: getFile DB read failed for \(uuid): \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }

        guard let record else {
            Self.log.debug("DuckAiNativeDataStore: getFile \(uuid) not found in DB")
            return nil
        }

        let fileURL = filesDirectoryURL.appendingPathComponent(record.filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Self.log.warning("DuckAiNativeDataStore: getFile \(uuid) DB record exists but file missing on disk")
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.log.error("DuckAiNativeDataStore: getFile disk read failed for \(uuid): \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.fileReadError(error)
        }

        Self.log.debug("DuckAiNativeDataStore: getFile \(uuid) loaded (\(data.count) bytes)")
        return DuckAiFileContent(uuid: record.uuid, chatId: record.chatId, data: data)
    }

    public func listFiles() throws -> [DuckAiFileMetadata] {
        do {
            let result = try dbQueue.read { db in
                let records = try FileRecord.fetchAll(db)
                return records.map { DuckAiFileMetadata(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.dataSize) }
            }
            Self.log.debug("DuckAiNativeDataStore: listFiles returned \(result.count) files")
            return result
        } catch {
            Self.log.error("DuckAiNativeDataStore: listFiles failed: \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteFile(uuid: String) throws {
        Self.log.debug("DuckAiNativeDataStore: deleteFile \(uuid)")
        let fileURL = filesDirectoryURL.appendingPathComponent(uuid)
        try? FileManager.default.removeItem(at: fileURL)

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_files WHERE uuid = ?", arguments: [uuid])
            }
        } catch {
            Self.log.error("DuckAiNativeDataStore: deleteFile DB delete failed for \(uuid): \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteAllFiles() throws {
        Self.log.debug("DuckAiNativeDataStore: deleteAllFiles")
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
            Self.log.error("DuckAiNativeDataStore: deleteAllFiles DB truncate failed: \(error.localizedDescription)")
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }
}
