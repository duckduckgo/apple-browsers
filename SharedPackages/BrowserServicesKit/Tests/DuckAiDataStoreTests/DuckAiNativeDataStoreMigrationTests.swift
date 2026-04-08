//
//  DuckAiNativeDataStoreMigrationTests.swift
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

import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import DuckAiDataStore

final class DuckAiNativeDataStoreMigrationTests: XCTestCase {

    private var tempDirectory: URL!
    private var databaseURL: URL!
    private var filesDirectory: URL!
    private var key: Data!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        databaseURL = tempDirectory.appendingPathComponent("db.sqlite")
        filesDirectory = tempDirectory.appendingPathComponent("files")
        key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }

        try! FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        databaseURL = nil
        filesDirectory = nil
        key = nil
        super.tearDown()
    }

    // MARK: - Orphaned File Cleanup

    func testWhenUnencryptedDbExistsThenOrphanedFilesAreDeletedOnInit() throws {
        createUnencryptedDatabase(at: databaseURL)
        let orphanedFile = filesDirectory.appendingPathComponent("orphaned-file.txt")
        try Data("plaintext data".utf8).write(to: orphanedFile)

        _ = try DuckAiNativeDataStore(databaseURL: databaseURL, filesDirectoryURL: filesDirectory, key: key)

        let contents = try FileManager.default.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(contents.isEmpty, "Orphaned files should be removed when database is recreated")
    }

    func testWhenUnencryptedDbExistsThenMultipleOrphanedFilesAreDeleted() throws {
        createUnencryptedDatabase(at: databaseURL)
        for i in 0..<3 {
            let file = filesDirectory.appendingPathComponent("file-\(i).dat")
            try Data("data \(i)".utf8).write(to: file)
        }

        _ = try DuckAiNativeDataStore(databaseURL: databaseURL, filesDirectoryURL: filesDirectory, key: key)

        let contents = try FileManager.default.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(contents.isEmpty)
    }

    func testWhenDbIsAlreadyEncryptedThenExistingFilesArePreserved() throws {
        // Create the store once to produce an encrypted DB
        let store = try DuckAiNativeDataStore(databaseURL: databaseURL, filesDirectoryURL: filesDirectory, key: key)
        try store.putFile(uuid: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890", chatId: "chat-1", data: Data("encrypted".utf8))

        let contentsBefore = try FileManager.default.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(contentsBefore.count, 1)

        // Re-open with the same key — should NOT wipe files
        _ = try DuckAiNativeDataStore(databaseURL: databaseURL, filesDirectoryURL: filesDirectory, key: key)

        let contentsAfter = try FileManager.default.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(contentsAfter.count, 1, "Files should be preserved when database opens normally")
    }

    func testWhenNoDbExistsThenEmptyFilesDirectoryStaysEmpty() throws {
        _ = try DuckAiNativeDataStore(databaseURL: databaseURL, filesDirectoryURL: filesDirectory, key: key)

        let contents = try FileManager.default.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(contents.isEmpty)
    }

    // MARK: - Helpers

    private func createUnencryptedDatabase(at url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "CREATE TABLE test (id INTEGER PRIMARY KEY)", nil, nil, nil)
        sqlite3_close(db)
    }
}
