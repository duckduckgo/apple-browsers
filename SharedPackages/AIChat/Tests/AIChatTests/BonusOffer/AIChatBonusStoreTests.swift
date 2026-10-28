//
//  AIChatBonusStoreTests.swift
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

@Suite("AIChatBonus - Store Tests")
struct AIChatBonusStoreTests {
    private let directoryURL = URL(fileURLWithPath: "/AIChatBonus", isDirectory: true)
    private var fileURL: URL { directoryURL.appendingPathComponent("record.json") }

    private let claimedRecord = AIChatBonusRecordMock.active

    private let fileSystem = MockAIChatBonusFileSystem()
    private let sut: AIChatBonusStore

    init() {
        sut = AIChatBonusStore(directoryURL: directoryURL, fileSystem: fileSystem)
    }

    // MARK: - Read

    @available(iOS 16, macOS 13, *)
    @Test("Check reading with no file returns no record", .timeLimit(.minutes(1)))
    func readWithNoFileReturnsNil() throws {
        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == nil)
        #expect(fileSystem.operations == [.read(fileURL)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a missing file reported by POSIX returns no record", .timeLimit(.minutes(1)))
    func missingFileReportedByPOSIXReturnsNil() throws {
        // GIVEN
        fileSystem.readError = POSIXError(.ENOENT)

        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a written record is read back", .timeLimit(.minutes(1)))
    func writtenRecordIsReadBack() throws {
        // GIVEN
        try sut.write(claimedRecord)

        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == claimedRecord)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a read failure other than a missing file makes the read throw", .timeLimit(.minutes(1)), arguments: [
        NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
        NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError),
        NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
    ])
    func readFailureMakesReadThrow(_ error: NSError) {
        // GIVEN
        fileSystem.readError = error

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.readFailed(domain: error.domain, code: error.code)) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a file that is not JSON makes the read throw", .timeLimit(.minutes(1)))
    func fileThatIsNotJSONMakesReadThrow() {
        // GIVEN
        fileSystem.files[fileURL] = Data("garbage".utf8)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.decodingFailed) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check record fields that do not decode make the read throw", .timeLimit(.minutes(1)))
    func recordFieldsThatDoNotDecodeMakeReadThrow() {
        // GIVEN
        fileSystem.files[fileURL] = Data(#"{"schemaVersion":1,"record":{"dismissed":"yes"}}"#.utf8) // wrong type for `dismissed`, should be `true` or `false`

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.decodingFailed) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check an unknown schema version makes the read throw", .timeLimit(.minutes(1)))
    func unknownSchemaVersionMakesReadThrow() {
        // GIVEN
        fileSystem.files[fileURL] = Data(#"{"schemaVersion":2,"somethingNew":true}"#.utf8)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.unsupportedSchemaVersion(2)) {
            try sut.read()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a stored record that breaks the invariant makes the read throw", .timeLimit(.minutes(1)))
    func storedRecordThatBreaksTheInvariantMakesReadThrow() {
        // GIVEN
        fileSystem.files[fileURL] = Data(#"{"schemaVersion":1,"record":{"bonusId":"id","dismissed":false}}"#.utf8)

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.invariantViolated) {
            try sut.read()
        }
    }

    // MARK: - Write

    @available(iOS 16, macOS 13, *)
    @Test("Check a write prepares the directory before writing the file", .timeLimit(.minutes(1)))
    func writePreparesTheDirectoryBeforeWritingTheFile() throws {
        // WHEN
        try sut.write(claimedRecord)

        // THEN
        #expect(fileSystem.operations == [.prepareDirectory(directoryURL), .write(fileURL)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check every write prepares the directory", .timeLimit(.minutes(1)))
    func everyWritePreparesTheDirectory() throws {
        // GIVEN
        try sut.write(AIChatBonusRecord(dismissed: true))

        // WHEN
        try sut.write(claimedRecord)

        // THEN
        #expect(fileSystem.operations == [
            .prepareDirectory(directoryURL), .write(fileURL),
            .prepareDirectory(directoryURL), .write(fileURL)
        ])
        #expect(try sut.read() == claimedRecord)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a failed directory preparation makes the write throw without writing", .timeLimit(.minutes(1)))
    func failedDirectoryPreparationMakesWriteThrowWithoutWriting() {
        // GIVEN
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        fileSystem.prepareDirectoryError = error

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.prepareDirectoryFailed(domain: error.domain, code: error.code)) {
            try sut.write(claimedRecord)
        }
        #expect(fileSystem.operations == [.prepareDirectory(directoryURL)])
        #expect(fileSystem.files.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check the stored data carries the schema version", .timeLimit(.minutes(1)))
    func storedDataCarriesTheSchemaVersion() throws {
        // WHEN
        try sut.write(claimedRecord)

        // THEN
        let data = try #require(fileSystem.files[fileURL])
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["record"] is [String: Any])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check the help page is stored next to the record", .timeLimit(.minutes(1)))
    func helpPageIsStoredNextToTheRecord() throws {
        // GIVEN
        let sut = AIChatBonusStore(directoryURL: directoryURL, fileSystem: fileSystem, helpPage: URL(string: "https://example.com/help")!)

        // WHEN
        try sut.write(claimedRecord)

        // THEN
        let data = try #require(fileSystem.files[fileURL])
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["helpPage"] as? String == "https://example.com/help")
        let text = try #require(String(bytes: data, encoding: .utf8))
        // The link reads as a normal URL, not with escaped slashes.
        #expect(text.contains("https://example.com/help"))
        #expect(try sut.read() == claimedRecord)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a file written without a help page still reads", .timeLimit(.minutes(1)))
    func fileWrittenWithoutAHelpPageStillReads() throws {
        // GIVEN
        fileSystem.files[fileURL] = Data(#"{"schemaVersion":1,"record":{"campaignName":"launch","dismissed":false}}"#.utf8)

        // WHEN
        let result = try sut.read()

        // THEN
        #expect(result == AIChatBonusRecord(campaignName: "launch"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a failed write makes the write throw", .timeLimit(.minutes(1)))
    func failedWriteMakesWriteThrow() throws {
        // GIVEN
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        fileSystem.writeError = error

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.writeFailed(domain: error.domain, code: error.code)) {
            try sut.write(claimedRecord)
        }
        #expect(fileSystem.files.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a record that breaks the invariant is never written", .timeLimit(.minutes(1)))
    func recordThatBreaksTheInvariantIsNeverWritten() {
        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.invariantViolated) {
            try sut.write(AIChatBonusRecord(bonusId: "id"))
        }
        #expect(fileSystem.operations.isEmpty)
    }

    // MARK: - Delete

    @available(iOS 16, macOS 13, *)
    @Test("Check delete removes the record", .timeLimit(.minutes(1)))
    func deleteRemovesTheRecord() throws {
        // GIVEN
        try sut.write(claimedRecord)
        #expect(try sut.read() != nil)

        // WHEN
        try sut.delete()

        // THEN
        #expect(try sut.read() == nil)
        #expect(fileSystem.operations.contains(.remove(fileURL)))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check deleting a missing record succeeds", .timeLimit(.minutes(1)), arguments: [
        CocoaError(.fileNoSuchFile) as Error,
        CocoaError(.fileReadNoSuchFile) as Error,
        POSIXError(.ENOENT) as Error
    ])
    func deletingAMissingRecordSucceeds(_ error: Error) {
        // GIVEN
        fileSystem.removeError = error

        // WHEN / THEN
        #expect(throws: Never.self) {
            try sut.delete()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check a failed delete throws", .timeLimit(.minutes(1)))
    func failedDeleteThrows() {
        // GIVEN
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        fileSystem.removeError = error

        // WHEN / THEN
        #expect(throws: AIChatBonusStoreError.deleteFailed(domain: error.domain, code: error.code)) {
            try sut.delete()
        }
    }

}
