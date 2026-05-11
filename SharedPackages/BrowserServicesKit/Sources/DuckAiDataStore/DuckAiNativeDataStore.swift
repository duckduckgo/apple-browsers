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

    /// Sentinel error stored in `setupResult` until the background setup task overwrites it.
    /// Under normal init flow this is never observed — `init` enqueues the setup task on the
    /// serial `setupQueue` before returning, so any later `sync` is FIFO-ordered behind it.
    private struct SetupNotCompletedError: Error {}

    private let filesDirectoryURL: URL
    private let encryptionKey: SymmetricKey
    private let setupQueue = DispatchQueue(label: "com.duckduckgo.duckai.nativedatastore.setup", qos: .userInitiated)
    private var setupResult: Result<DatabaseQueue, Error> = .failure(SetupNotCompletedError())

    // Non-blocking probe of background setup state. Read by `setupSucceeded` from
    // any thread; written exactly once when the deferred work finishes.
    private let setupStateLock = NSLock()
    private var _setupSucceeded: Bool?

    /// Non-blocking probe of background DB setup state.
    /// - Returns: `nil` while setup is in flight, `true` if it completed successfully,
    ///   `false` if it failed. Safe to call from any thread; never blocks on the
    ///   setup queue and so is safe to evaluate on the main thread during launch.
    public var setupSucceeded: Bool? {
        setupStateLock.lock()
        defer { setupStateLock.unlock() }
        return _setupSucceeded
    }

    /// Creates an encrypted data store backed by SQLCipher.
    ///
    /// If an existing unencrypted database is found, it is deleted and recreated
    /// as an encrypted database. This handles the migration from the pre-encryption
    /// storage format.
    ///
    /// The database open and migrations run asynchronously on a background queue;
    /// errors surface at the first read/write call rather than from `init`. To observe
    /// the async setup outcome (e.g. for telemetry) pass `setupCompletion`; it is
    /// invoked exactly once on the setup queue when the DB is ready or has failed.
    ///
    /// - Parameters:
    ///   - databaseURL: Path to the SQLite database file.
    ///   - filesDirectoryURL: Directory for storing file attachments on disk.
    ///   - key: 256-bit symmetric key used for SQLCipher encryption.
    ///   - setupCompletion: Optional callback invoked once the background DB open
    ///     and migrations finish. Called on the internal setup queue, which means
    ///     the first DB read/write from any other thread queues behind it — the
    ///     closure should be fast (e.g. fire a pixel) and must not block.
    public init(
        databaseURL: URL,
        filesDirectoryURL: URL,
        key: Data,
        setupCompletion: ((Result<Void, Error>) -> Void)? = nil
    ) throws {
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

        setupQueue.async { [filesDirectoryURL] in
            let result: Result<DatabaseQueue, Error> = Result {
                do {
                    let queue = try Self.openDatabase(at: databaseURL, key: key, filesDirectoryURL: filesDirectoryURL)
                    try Self.runMigrations(on: queue)
                    return queue
                } catch let error as DuckAiNativeDataStoreError {
                    throw error
                } catch {
                    throw DuckAiNativeDataStoreError.databaseError(error)
                }
            }
            self.setupResult = result
            switch result {
            case .success:
                self.setupStateLock.lock()
                self._setupSucceeded = true
                self.setupStateLock.unlock()
                setupCompletion?(.success(()))
            case .failure(let error):
                self.setupStateLock.lock()
                self._setupSucceeded = false
                self.setupStateLock.unlock()
                setupCompletion?(.failure(error))
            }
        }
    }

    /// Blocks the caller until background setup completes, then returns the prepared
    /// `DatabaseQueue` or rethrows the wrapped setup error.
    private func dbQueue() throws -> DatabaseQueue {
        try setupQueue.sync {
            try self.setupResult.get()
        }
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
        let queue = try dbQueue()
        let record = ChatRecord(chatId: chatId, data: data)
        do {
            try queue.write { db in
                try record.save(db)
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func putChats(_ chats: [DuckAiChatRecord]) throws {
        let queue = try dbQueue()
        do {
            try queue.write { db in
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
        let queue = try dbQueue()
        do {
            return try queue.read { db in
                guard let record = try ChatRecord.fetchOne(db, key: chatId) else { return nil }
                return DuckAiChatRecord(chatId: record.chatId, data: record.data)
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func getAllChats() throws -> [DuckAiChatRecord] {
        let queue = try dbQueue()
        do {
            return try queue.read { db in
                let records = try ChatRecord.fetchAll(db)
                return records.map { DuckAiChatRecord(chatId: $0.chatId, data: $0.data) }
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteChat(chatId: String) throws {
        let queue = try dbQueue()
        do {
            try queue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_chats WHERE chatId = ?", arguments: [chatId])
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteAllChats() throws {
        let queue = try dbQueue()
        do {
            try queue.write { db in
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
        let queue = try dbQueue()
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
            try queue.write { db in
                try record.save(db)
            }
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        let normalizedUUID = try validatedFileUUID(for: uuid)
        let queue = try dbQueue()
        let fileURL = filesDirectoryURL.appendingPathComponent(normalizedUUID)

        let record: FileRecord?
        do {
            record = try queue.read { db in
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
        let queue = try dbQueue()
        do {
            return try queue.read { db in
                let records = try FileRecord.fetchAll(db)
                return records.map { DuckAiFileMetadata(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.dataSize) }
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteFile(uuid: String) throws {
        let normalizedUUID = try validatedFileUUID(for: uuid)
        let queue = try dbQueue()
        let fileURL = filesDirectoryURL.appendingPathComponent(normalizedUUID)
        try? FileManager.default.removeItem(at: fileURL)

        do {
            try queue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_files WHERE uuid = ?", arguments: [normalizedUUID])
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteFiles(chatId: String) throws {
        let queue = try dbQueue()
        let fileNames: [String]
        do {
            fileNames = try queue.read { db in
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
            try queue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_files WHERE chatId = ?", arguments: [chatId])
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }

    public func deleteAllFiles() throws {
        let queue = try dbQueue()
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(at: filesDirectoryURL, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        do {
            try queue.write { db in
                try db.execute(sql: "DELETE FROM duck_ai_files")
            }
        } catch {
            throw DuckAiNativeDataStoreError.databaseError(error)
        }
    }
}
