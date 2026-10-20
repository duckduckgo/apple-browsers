//
//  AIChatBonusStoreIntegrationTests.swift
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
import Testing
@testable import AIChat

/// Uses the real file system, so it checks what `FileManager` does rather than what the mock assumes.
@Suite("AIChatBonus - Store Integration Tests")
final class AIChatBonusStoreIntegrationTests {
    private let rootURL: URL
    private let directoryURL: URL
    private var fileURL: URL { directoryURL.appendingPathComponent("record.json") }
    private let sut: AIChatBonusStore

    init() {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        directoryURL = rootURL.appendingPathComponent("AIChatBonus", isDirectory: true)
        sut = AIChatBonusStore(directoryURL: directoryURL, fileSystem: AIChatBonusFileSystem())
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    // MARK: - Read

    @available(iOS 16, macOS 13, *)
    @Test("Check reading when nothing was ever written returns no record", .timeLimit(.minutes(1)))
    func readingWhenNothingWasWrittenReturnsNil() throws {
        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check reading with the directory but no file returns no record", .timeLimit(.minutes(1)))
    func readingWithTheDirectoryButNoFileReturnsNil() throws {
        // GIVEN
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a file that can't be read makes the read throw", .timeLimit(.minutes(1)))
    func fileThatCannotBeReadMakesReadThrow() throws {
        // GIVEN
        // A directory at the record's path exists but can't be read as data, so the failure isn't a missing file.
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

        // WHEN / THEN
        let error = #expect(throws: AIChatBonusStoreError.self) {
            try sut.read()
        }
        guard case .readFailed = error else {
            Issue.record("Expected readFailed, got \(String(describing: error))")
            return
        }
    }

    // MARK: - Write

    @available(iOS 16, macOS 13, *)
    @Test("Check a write creates the missing directories and excludes the record's from backup", .timeLimit(.minutes(1)))
    func writeCreatesTheMissingDirectoriesAndExcludesFromBackup() throws {
        // WHEN
        try sut.write(AIChatBonusRecordMock.active)

        // THEN
        #expect(try isExcludedFromBackup(directoryURL))
        #expect(try sut.read() == AIChatBonusRecordMock.active)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a write over an existing record keeps the directory excluded from backup", .timeLimit(.minutes(1)))
    func writeOverAnExistingRecordKeepsTheDirectoryExcludedFromBackup() throws {
        // GIVEN
        try sut.write(AIChatBonusRecord(dismissed: true))

        // WHEN
        // The directory exists now, and the atomic write replaces the file.
        try sut.write(AIChatBonusRecordMock.active)

        // THEN
        #expect(try isExcludedFromBackup(directoryURL))
        #expect(try sut.read() == AIChatBonusRecordMock.active)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a write into a recreated directory excludes it from backup again", .timeLimit(.minutes(1)))
    func writeIntoARecreatedDirectoryExcludesItAgain() throws {
        // GIVEN
        try sut.write(AIChatBonusRecordMock.active)
        try FileManager.default.removeItem(at: directoryURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        #expect(try isExcludedFromBackup(directoryURL) == false)

        // WHEN
        try sut.write(AIChatBonusRecordMock.active)

        // THEN
        #expect(try isExcludedFromBackup(directoryURL))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a directory that can't be created makes the write throw without writing", .timeLimit(.minutes(1)))
    func directoryThatCannotBeCreatedMakesWriteThrowWithoutWriting() throws {
        // GIVEN
        // A file at the directory's path, so the directory can't be created.
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: directoryURL)

        // WHEN / THEN
        let error = #expect(throws: AIChatBonusStoreError.self) {
            try sut.write(AIChatBonusRecordMock.active)
        }
        guard case .excludeFromBackupFailed = error else {
            Issue.record("Expected excludeFromBackupFailed, got \(String(describing: error))")
            return
        }
        #expect(try Data(contentsOf: directoryURL) == Data("not a directory".utf8))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a write leaves only the record in the directory", .timeLimit(.minutes(1)))
    func writeLeavesOnlyTheRecordInTheDirectory() throws {
        // WHEN
        try sut.write(AIChatBonusRecord(dismissed: true))
        try sut.write(AIChatBonusRecordMock.active)

        // THEN
        // The atomic write's temporary file is gone once the write returns.
        let contents = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        #expect(contents == ["record.json"])
    }

    // MARK: - Delete

    @available(iOS 16, macOS 13, *)
    @Test("Check delete removes the record from disk", .timeLimit(.minutes(1)))
    func deleteRemovesTheRecordFromDisk() throws {
        // GIVEN
        try sut.write(AIChatBonusRecordMock.active)

        // WHEN
        try sut.delete()

        // THEN
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
        #expect(try sut.read() == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check deleting when nothing was ever written succeeds", .timeLimit(.minutes(1)))
    func deletingWhenNothingWasWrittenSucceeds() {
        // WHEN / THEN
        #expect(throws: Never.self) {
            try sut.delete()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check deleting twice succeeds", .timeLimit(.minutes(1)))
    func deletingTwiceSucceeds() throws {
        // GIVEN
        try sut.write(AIChatBonusRecordMock.active)
        try sut.delete()

        // WHEN / THEN
        #expect(throws: Never.self) {
            try sut.delete()
        }
    }

    // MARK: - Helpers

    private func isExcludedFromBackup(_ url: URL) throws -> Bool {
        // A fresh URL, so the value comes from disk rather than the URL's cache.
        let url = URL(fileURLWithPath: url.path, isDirectory: true)
        return try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

}
