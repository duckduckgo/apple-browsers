//
//  DuckAiNativeDataStoreFilesTests.swift
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
import XCTest
@testable import DuckAiDataStore

final class DuckAiNativeDataStoreFilesTests: XCTestCase {

    private var tempDirectory: URL!
    private var filesDirectory: URL!
    private var sut: DuckAiNativeDataStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let databaseURL = tempDirectory.appendingPathComponent("db.sqlite")
        filesDirectory = tempDirectory.appendingPathComponent("files")
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        sut = try! DuckAiNativeDataStore(databaseURL: databaseURL, filesDirectoryURL: filesDirectory, key: key)
    }

    override func tearDown() {
        sut = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        filesDirectory = nil
        super.tearDown()
    }

    func testWhenPutFileThenGetFileReturnsIt() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let chatId = "chat-1"
        let data = Data("hello world".utf8)

        try sut.putFile(uuid: uuid, chatId: chatId, data: data)

        let result = try sut.getFile(uuid: uuid)
        XCTAssertEqual(result, DuckAiFileContent(uuid: uuid, chatId: chatId, data: data))
    }

    func testWhenPutFileThenFileExistsOnDiskEncrypted() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let data = Data("file content".utf8)

        try sut.putFile(uuid: uuid, chatId: "chat-1", data: data)

        let fileURL = filesDirectory.appendingPathComponent(uuid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let rawBytes = try Data(contentsOf: fileURL)
        XCTAssertNotEqual(rawBytes, data, "File on disk should be encrypted, not plaintext")
    }

    func testWhenListFilesThenReturnsMetadataWithoutFileIO() throws {
        let uuid1 = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let uuid2 = "B2C3D4E5-F6A7-8901-BCDE-F12345678901"
        let data1 = Data("data one".utf8)
        let data2 = Data("data two".utf8)

        try sut.putFile(uuid: uuid1, chatId: "chat-1", data: data1)
        try sut.putFile(uuid: uuid2, chatId: "chat-2", data: data2)

        let metadata = try sut.listFiles()
        XCTAssertEqual(metadata.count, 2)

        let sorted = metadata.sorted { $0.uuid < $1.uuid }
        XCTAssertEqual(sorted[0], DuckAiFileMetadata(uuid: uuid1, chatId: "chat-1", dataSize: data1.count))
        XCTAssertEqual(sorted[1], DuckAiFileMetadata(uuid: uuid2, chatId: "chat-2", dataSize: data2.count))
    }

    func testWhenDeleteFileThenFileRemovedFromDiskAndDb() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let data = Data("to delete".utf8)

        try sut.putFile(uuid: uuid, chatId: "chat-1", data: data)
        try sut.deleteFile(uuid: uuid)

        XCTAssertNil(try sut.getFile(uuid: uuid))
        let fileURL = filesDirectory.appendingPathComponent(uuid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testWhenDeleteAllFilesThenAllRemovedFromDiskAndDb() throws {
        let uuid1 = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let uuid2 = "B2C3D4E5-F6A7-8901-BCDE-F12345678901"

        try sut.putFile(uuid: uuid1, chatId: "chat-1", data: Data("one".utf8))
        try sut.putFile(uuid: uuid2, chatId: "chat-2", data: Data("two".utf8))

        try sut.deleteAllFiles()

        let files = try sut.listFiles()
        XCTAssertTrue(files.isEmpty)

        let contents = try FileManager.default.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil)
        XCTAssertTrue(contents.isEmpty)
    }

    func testWhenGetNonExistentFileThenReturnsNil() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let result = try sut.getFile(uuid: uuid)
        XCTAssertNil(result)
    }

    func testWhenPutFileWithSameUuidThenItUpdates() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let initialData = Data("initial".utf8)
        let updatedData = Data("updated content".utf8)

        try sut.putFile(uuid: uuid, chatId: "chat-1", data: initialData)
        try sut.putFile(uuid: uuid, chatId: "chat-1", data: updatedData)

        let files = try sut.listFiles()
        XCTAssertEqual(files.count, 1)

        let result = try sut.getFile(uuid: uuid)
        XCTAssertEqual(result, DuckAiFileContent(uuid: uuid, chatId: "chat-1", data: updatedData))
    }

    // MARK: - UUID Validation

    func testWhenPutFileWithInvalidUuidThenThrowsInvalidFileIdentifier() {
        XCTAssertThrowsError(try sut.putFile(uuid: "../chats.db", chatId: "chat-1", data: Data("malicious".utf8))) { error in
            guard case DuckAiNativeDataStoreError.invalidFileIdentifier = error else {
                return XCTFail("Expected invalidFileIdentifier, got \(error)")
            }
        }
    }

    func testWhenGetFileWithInvalidUuidThenThrowsInvalidFileIdentifier() {
        XCTAssertThrowsError(try sut.getFile(uuid: "../chats.db")) { error in
            guard case DuckAiNativeDataStoreError.invalidFileIdentifier = error else {
                return XCTFail("Expected invalidFileIdentifier, got \(error)")
            }
        }
    }

    func testWhenDeleteFileWithInvalidUuidThenThrowsInvalidFileIdentifier() {
        XCTAssertThrowsError(try sut.deleteFile(uuid: "../chats.db")) { error in
            guard case DuckAiNativeDataStoreError.invalidFileIdentifier = error else {
                return XCTFail("Expected invalidFileIdentifier, got \(error)")
            }
        }
    }

    // MARK: - Decryption Failure

    func testWhenFileOnDiskIsUnencryptedThenGetFileThrowsFileReadError() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let plaintext = Data("not encrypted".utf8)

        // Write the DB record via the store, then overwrite the file with raw plaintext
        try sut.putFile(uuid: uuid, chatId: "chat-1", data: plaintext)
        let fileURL = filesDirectory.appendingPathComponent(uuid)
        try plaintext.write(to: fileURL)

        XCTAssertThrowsError(try sut.getFile(uuid: uuid)) { error in
            guard case DuckAiNativeDataStoreError.fileReadError = error else {
                return XCTFail("Expected fileReadError, got \(error)")
            }
        }
    }

    func testWhenFileIsCorruptedThenGetFileThrowsFileReadError() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let data = Data("some content".utf8)

        try sut.putFile(uuid: uuid, chatId: "chat-1", data: data)
        let fileURL = filesDirectory.appendingPathComponent(uuid)
        // Corrupt the encrypted file by truncating it
        try Data("bad".utf8).write(to: fileURL)

        XCTAssertThrowsError(try sut.getFile(uuid: uuid)) { error in
            guard case DuckAiNativeDataStoreError.fileReadError = error else {
                return XCTFail("Expected fileReadError, got \(error)")
            }
        }
    }

    func testWhenDeleteFilesByChatIdThenOnlyThatChatsFilesAreRemoved() throws {
        let uuidChat1A = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let uuidChat1B = "B2C3D4E5-F6A7-8901-BCDE-F12345678901"
        let uuidChat2 = "C3D4E5F6-A7B8-9012-CDEF-123456789012"

        try sut.putFile(uuid: uuidChat1A, chatId: "chat-1", data: Data("a".utf8))
        try sut.putFile(uuid: uuidChat1B, chatId: "chat-1", data: Data("b".utf8))
        try sut.putFile(uuid: uuidChat2, chatId: "chat-2", data: Data("c".utf8))

        try sut.deleteFiles(chatId: "chat-1")

        let remaining = try sut.listFiles()
        XCTAssertEqual(remaining.map { $0.uuid }, [uuidChat2])

        XCTAssertFalse(FileManager.default.fileExists(atPath: filesDirectory.appendingPathComponent(uuidChat1A).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: filesDirectory.appendingPathComponent(uuidChat1B).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesDirectory.appendingPathComponent(uuidChat2).path))
    }

    func testWhenDeleteFilesForChatWithNoFilesThenNoError() throws {
        XCTAssertNoThrow(try sut.deleteFiles(chatId: "non-existent"))
    }

    func testWhenFileEncryptedWithDifferentKeyThenGetFileThrowsFileReadError() throws {
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let data = Data("secret".utf8)

        try sut.putFile(uuid: uuid, chatId: "chat-1", data: data)

        // Overwrite with data encrypted using a different key
        let differentKey = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(data, using: differentKey)
        let fileURL = filesDirectory.appendingPathComponent(uuid)
        try sealed.combined!.write(to: fileURL)

        XCTAssertThrowsError(try sut.getFile(uuid: uuid)) { error in
            guard case DuckAiNativeDataStoreError.fileReadError = error else {
                return XCTFail("Expected fileReadError, got \(error)")
            }
        }
    }
}
