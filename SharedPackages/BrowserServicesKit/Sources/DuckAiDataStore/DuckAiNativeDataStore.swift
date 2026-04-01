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

public final class DuckAiNativeDataStore: DuckAiNativeDataStoring {

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
            throw DuckAiNativeDataStoreError.directoryCreationFailed(error)
        }

        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }

        try runMigrations()
    }

    // MARK: - Migrations

    private func runMigrations() throws {
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

    struct FileRecord: Codable, FetchableRecord, PersistableRecord {
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

    public func putFile(uuid: String, chatId: String, data: Data) throws {
        fatalError("Implemented in Task 3")
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        fatalError("Implemented in Task 3")
    }

    public func listFiles() throws -> [DuckAiFileMetadata] {
        fatalError("Implemented in Task 3")
    }

    public func deleteFile(uuid: String) throws {
        fatalError("Implemented in Task 3")
    }

    public func deleteAllFiles() throws {
        fatalError("Implemented in Task 3")
    }
}
