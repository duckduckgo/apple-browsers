//
//  GRDBSecureStorageDatabaseProviderTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import XCTest
import CryptoKit
import SecureStorage
import GRDB

private class TestGRDBDatabaseProvider: GRDBSecureStorageDatabaseProvider {

    static func migrateV1(database: Database) throws {
        try database.create(table: TestGRDBModel.databaseTableName) {
            $0.column(TestGRDBModel.Columns.id.name, .integer)
            $0.column(TestGRDBModel.Columns.username.name, .text)
        }
    }

    init(file: URL, key: Data) throws {
        try super.init(file: file, key: key) { databaseMigrator in
            databaseMigrator.registerMigration("v1", migrate: Self.migrateV1(database:))
        }
    }

    func insert(testModel: TestGRDBModel) throws {
        try db.write {
            try testModel.insert($0)
        }
    }

    func fetchTestModels() throws -> [TestGRDBModel] {
        try db.read {
            try TestGRDBModel.fetchAll($0)
        }
    }

}

private struct TestGRDBModel: PersistableRecord, FetchableRecord, Equatable {

    enum Columns: String, ColumnExpression {
        case id, username
    }

    let id: Int
    let username: String

    init(id: Int, username: String) {
        self.id = id
        self.username = username
    }

    init(row: Row) {
        id = row[Columns.id]
        username = row[Columns.username]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.username] = username
    }

    static var databaseTableName: String = "test_grdb_model"

}

final class GRDBSecureStorageDatabaseProviderTests: XCTestCase {

    func testWhenCreatingGRDBDatabase_ThenDatabaseIsMigrated_AndDataCanBeReadAndWritten() throws {
        let temporaryDatabaseURL = createTemporaryFileURL()
        let keyData = SymmetricKey(size: .bits256).dataRepresentation
        let testProvider = try TestGRDBDatabaseProvider(file: temporaryDatabaseURL, key: keyData)

        let testModel = TestGRDBModel(id: 1, username: "dax")
        try testProvider.insert(testModel: testModel)
        let modelFromDatabase = try testProvider.fetchTestModels().first

        XCTAssertEqual(testModel, modelFromDatabase)
    }

    func testWhenDatabaseIsCorrupt_ThenItIsRecreated_AndTheCorruptDatabaseIsMovedToABackup() throws {
        let temporaryDatabaseURL = createTemporaryFileURL()
        let keyData = SymmetricKey(size: .bits256).dataRepresentation
        let backupURL = temporaryDatabaseURL.appendingPathExtension("bak")

        addTeardownBlock {
            try? FileManager.default.removeItem(at: backupURL)
        }

        try! "asdf".data(using: .utf8)!.write(to: temporaryDatabaseURL)
        _ = try TestGRDBDatabaseProvider(file: temporaryDatabaseURL, key: keyData)

        // Check that the original file was moved to a backup file:
        XCTAssertEqual(try! Data(contentsOf: backupURL), "asdf".data(using: .utf8))

        let database = try TestGRDBDatabaseProvider(file: temporaryDatabaseURL, key: keyData)

        // Check that the database can now be used:
        let testModel = TestGRDBModel(id: 1, username: "dax")
        try database.insert(testModel: testModel)
        let modelFromDatabase = try database.fetchTestModels().first

        XCTAssertEqual(testModel, modelFromDatabase)
    }

    func testWhenCreatingDatabaseFilePath_ThenDatabaseFilePathIncludesDirectoryAndFileName() {
        let databaseFilePath = GRDBSecureStorageDatabaseProvider.databaseFilePath(directoryName: "Test", fileName: "Database.db")

        XCTAssert(databaseFilePath.absoluteString.hasSuffix("Test/Database.db"))

        let databaseFilePathAppGroup = GRDBSecureStorageDatabaseProvider.databaseFilePath(directoryName: "Test", fileName: "Database.db", appGroupIdentifier: "TEST")

        XCTAssert(databaseFilePathAppGroup.absoluteString.hasSuffix("Test/Database.db"))

        XCTAssertNotEqual(databaseFilePath, databaseFilePathAppGroup)
    }

    func createTemporaryFileURL() -> URL {
        let directory = NSTemporaryDirectory()
        let filename = UUID().uuidString
        let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(filename).appendingPathExtension("db")

        // Add a teardown block to delete any file at `fileURL`.
        addTeardownBlock {
            do {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                    XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path))
                }
            } catch {
                XCTFail("Error while deleting temporary file: \(error)")
            }
        }

        return fileURL
    }

}
