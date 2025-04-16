//
//  ImportArchiveReaderTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import Core
import ZIPFoundation

final class ImportArchiveReaderTests: XCTestCase {

    private var reader: ImportArchiveReader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        reader = ImportArchiveReader()
    }

    override func tearDownWithError() throws {
        reader = nil
        try super.tearDownWithError()
    }

    // MARK: - Content Type Tests

    func testWhenGivenCSVDataThenContentTypeIsPasswordsOnly() {
        let contents = ImportArchiveContents(passwords: ["csv data"], bookmarks: [])

        XCTAssertEqual(contents.type, .passwordsOnly)
    }

    func testWhenGivenHtmlDataThenContentTypeIsBookmarksOnly() {
        let contents = ImportArchiveContents(passwords: [], bookmarks: ["html data"])

        XCTAssertEqual(contents.type, .bookmarksOnly)
    }

    func testWhenGivenCsvAndHtmlDataThenContentTypeIsPasswordsAndBookmarks() {
        let contents = ImportArchiveContents(passwords: ["csv data"], bookmarks: ["html data"])

        XCTAssertEqual(contents.type, .both)
    }

    func testWhenGivenNoCsvOrHtmlDataThenContentTypeIsNone() {
        let contents = ImportArchiveContents(passwords: [], bookmarks: [])

        XCTAssertEqual(contents.type, .none)
    }

    // MARK: - Archive Reading Tests

    func testWhenArchiveContainsCsvAndUnsupportedFileThenPasswordsReadAndOtherFileIgnored() throws {
        let archiveURL = try createTestArchive(
            files: [
                "passwords.csv": "username,password",
                "other.txt": "should be ignored"
            ]
        )

        let contents = try reader.readContents(from: archiveURL)

        XCTAssertEqual(contents.passwords.count, 1)
        XCTAssertEqual(contents.passwords.first, "username,password")
        XCTAssertTrue(contents.bookmarks.isEmpty)
        XCTAssertEqual(contents.type, .passwordsOnly)
    }

    func testWhenArchiveContainsHtmlAndUnsupportedFileThenBookmarksReadAndOtherFileIgnored() throws {
        let archiveURL = try createTestArchive(
            files: [
                "bookmarks.html": "<html>bookmark data</html>",
                "other.txt": "should be ignored"
            ]
        )

        let contents = try reader.readContents(from: archiveURL)

        XCTAssertEqual(contents.bookmarks.count, 1)
        XCTAssertEqual(contents.bookmarks.first, "<html>bookmark data</html>")
        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertEqual(contents.type, .bookmarksOnly)
    }

    func testWhenArchiveContainsCsvAndHtmlAndUnsupportedFileThenPasswordsAndBookmarksReadAndOtherFileIgnored() throws {
        let archiveURL = try createTestArchive(
            files: [
                "passwords.csv": "username,password",
                "bookmarks.html": "<html>bookmark data</html>",
                "other.txt": "should be ignored"
            ]
        )

        let contents = try reader.readContents(from: archiveURL)

        XCTAssertEqual(contents.passwords.count, 1)
        XCTAssertEqual(contents.bookmarks.count, 1)
        XCTAssertEqual(contents.type, .both)
    }

    func testWhenArchiveContainsNoUnsupportedFileThenNoFilesRead() throws {
        let archiveURL = try createTestArchive(
            files: [
                "other1.txt": "some text",
                "other2.doc": "some doc"
            ]
        )

        let contents = try reader.readContents(from: archiveURL)

        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertTrue(contents.bookmarks.isEmpty)
        XCTAssertEqual(contents.type, .none)
    }

    func testWhenArchiveContainsPasswordsWithInvalidContentsThenNoPasswordsRead() throws {
        let invalidData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        let archiveURL = try createTestArchive(
            files: ["passwords.csv": invalidData]
        )

        let contents = try reader.readContents(from: archiveURL)

        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertEqual(contents.type, .none)
    }

    func testWhenArchiveIsNotZipFileThenThrowsError() throws {
        let invalidArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.zip")
        try Data("not a zip file".utf8).write(to: invalidArchiveURL)

        XCTAssertThrowsError(try reader.readContents(from: invalidArchiveURL))
    }

    // MARK: - Helper Methods

    private func createTestArchive(files: [String: Any]) throws -> URL {
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)

        for (filename, content) in files {
            if let stringContent = content as? String {
                try archive.addEntry(
                    with: filename,
                    type: .file,
                    uncompressedSize: Int64(stringContent.utf8.count),
                    provider: { _, _ in
                        Data(stringContent.utf8)
                    }
                )
            } else if let data = content as? Data {
                try archive.addEntry(
                    with: filename,
                    type: .file,
                    uncompressedSize: Int64(data.count),
                    provider: { _, _ in
                        data
                    }
                )
            }
        }

        return archiveURL
    }
}
