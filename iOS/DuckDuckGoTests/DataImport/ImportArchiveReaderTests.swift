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
    private var mockFeatureFlagger: MockFeatureFlagger!

    override func setUpWithError() throws {
        try super.setUpWithError()
        reader = ImportArchiveReader()
        mockFeatureFlagger = MockFeatureFlagger()
    }

    override func tearDownWithError() throws {
        reader = nil
        mockFeatureFlagger = nil
        try super.tearDownWithError()
    }

    // MARK: - Content Type Tests

    func testWhenGivenCSVDataThenContentTypeIsPasswordsOnly() {
        let contents = ImportArchiveContents(passwords: ["csv data"], bookmarks: [], creditCards: [])

        XCTAssertEqual(contents.type, .passwordsOnly)
    }

    func testWhenGivenHtmlDataThenContentTypeIsBookmarksOnly() {
        let contents = ImportArchiveContents(passwords: [], bookmarks: ["html data"], creditCards: [])

        XCTAssertEqual(contents.type, .bookmarksOnly)
    }

    func testWhenGivenCreditCardDataThenContentTypeIsCreditCardsOnly() {
        let contents = ImportArchiveContents(passwords: [], bookmarks: [], creditCards: ["json data"])

        XCTAssertEqual(contents.type, .creditCardsOnly)
    }

    func testWhenGivenCsvAndHtmlDataThenContentTypeIsOther() {
        let contents = ImportArchiveContents(passwords: ["csv data"], bookmarks: ["html data"], creditCards: [])

        XCTAssertEqual(contents.type, .other)
    }

    func testWhenGivenAllThreeDataTypesThenContentTypeIsOther() {
        let contents = ImportArchiveContents(passwords: ["csv data"], bookmarks: ["html data"], creditCards: ["json data"])

        XCTAssertEqual(contents.type, .other)
    }

    func testWhenGivenNoCsvOrHtmlOrCreditCardDataThenContentTypeIsNone() {
        let contents = ImportArchiveContents(passwords: [], bookmarks: [], creditCards: [])

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

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertEqual(contents.passwords.count, 1)
        XCTAssertEqual(contents.passwords.first, "username,password")
        XCTAssertTrue(contents.bookmarks.isEmpty)
        XCTAssertTrue(contents.creditCards.isEmpty)
        XCTAssertEqual(contents.type, .passwordsOnly)
    }

    func testWhenArchiveContainsHtmlAndUnsupportedFileThenBookmarksReadAndOtherFileIgnored() throws {
        let archiveURL = try createTestArchive(
            files: [
                "bookmarks.html": "<html>bookmark data</html>",
                "other.txt": "should be ignored"
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertEqual(contents.bookmarks.count, 1)
        XCTAssertEqual(contents.bookmarks.first, "<html>bookmark data</html>")
        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertTrue(contents.creditCards.isEmpty)
        XCTAssertEqual(contents.type, .bookmarksOnly)
    }

    func testWhenArchiveContainsValidPaymentCardsJsonAndFeatureEnabledThenCreditCardsRead() throws {
        mockFeatureFlagger.enabledFeatureFlags.append(.autofillCreditCards)

        let paymentCardsJson = """
        {
            "payment_cards": [
                {
                    "card_number": "4111111111111111",
                    "card_holder": "John Doe"
                }
            ]
        }
        """

        let archiveURL = try createTestArchive(
            files: [
                "cards.json": paymentCardsJson
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertEqual(contents.creditCards.count, 1)
        XCTAssertEqual(contents.creditCards.first, paymentCardsJson)
        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertTrue(contents.bookmarks.isEmpty)
        XCTAssertEqual(contents.type, .creditCardsOnly)
    }

    func testWhenArchiveContainsValidPaymentCardsJsonButFeatureDisabledThenCreditCardsNotRead() throws {
        let paymentCardsJson = """
        {
            "payment_cards": [
                {
                    "card_number": "4111111111111111",
                    "card_holder": "John Doe"
                }
            ]
        }
        """

        let archiveURL = try createTestArchive(
            files: [
                "cards.json": paymentCardsJson
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertTrue(contents.creditCards.isEmpty)
        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertTrue(contents.bookmarks.isEmpty)
        XCTAssertEqual(contents.type, .none)
    }

    func testWhenArchiveContainsJsonWithoutPaymentCardsThenCreditCardsNotRead() throws {
        let regularJson = """
        {
            "some_data": "value",
            "other_field": 123
        }
        """

        let archiveURL = try createTestArchive(
            files: [
                "data.json": regularJson
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertTrue(contents.creditCards.isEmpty)
        XCTAssertEqual(contents.type, .none)
    }

    func testWhenArchiveContainsCsvAndHtmlAndCreditCardsThenAllThreeTypesRead() throws {
        mockFeatureFlagger.enabledFeatureFlags.append(.autofillCreditCards)

        let paymentCardsJson = """
        {
            "payment_cards": []
        }
        """

        let archiveURL = try createTestArchive(
            files: [
                "passwords.csv": "username,password",
                "bookmarks.html": "<html>bookmark data</html>",
                "cards.json": paymentCardsJson,
                "other.txt": "should be ignored"
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertEqual(contents.passwords.count, 1)
        XCTAssertEqual(contents.bookmarks.count, 1)
        XCTAssertEqual(contents.creditCards.count, 1)
        XCTAssertEqual(contents.type, .other)
    }

    func testWhenArchiveContainsNoSupportedFilesThenNoFilesRead() throws {
        let archiveURL = try createTestArchive(
            files: [
                "other1.txt": "some text",
                "other2.doc": "some doc"
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertTrue(contents.bookmarks.isEmpty)
        XCTAssertTrue(contents.creditCards.isEmpty)
        XCTAssertEqual(contents.type, .none)
    }

    func testWhenArchiveContainsPasswordsWithInvalidContentsThenNoPasswordsRead() throws {
        let invalidData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        let archiveURL = try createTestArchive(
            files: ["passwords.csv": invalidData]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertTrue(contents.passwords.isEmpty)
        XCTAssertEqual(contents.type, .none)
    }

    func testWhenArchiveContainsCreditCardsWithInvalidContentsThenNoCreditCardsRead() throws {
        let invalidData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        let archiveURL = try createTestArchive(
            files: ["cards.json": invalidData]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertTrue(contents.creditCards.isEmpty)
        XCTAssertEqual(contents.type, .none)
    }

    func testWhenArchiveContainsMultipleCsvFilesThenAllPasswordFilesRead() throws {
        let archiveURL = try createTestArchive(
            files: [
                "passwords1.csv": "user1,pass1",
                "passwords2.CSV": "user2,pass2", // uppercase extension
                "subfolder/passwords3.csv": "user3,pass3"
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertEqual(contents.passwords.count, 3)
        XCTAssertTrue(contents.passwords.contains("user1,pass1"))
        XCTAssertTrue(contents.passwords.contains("user2,pass2"))
        XCTAssertTrue(contents.passwords.contains("user3,pass3"))
    }

    func testWhenArchiveContainsMultiplePaymentCardsJsonFilesThenAllRead() throws {
        mockFeatureFlagger.enabledFeatureFlags.append(.autofillCreditCards)

        let paymentCardsJson1 = """
        { "payment_cards": [{"number": "1234"}] }
        """
        let paymentCardsJson2 = """
        { "payment_cards": [{"number": "5678"}] }
        """
        let nonPaymentJson = """
        { "other_data": "value" }
        """

        let archiveURL = try createTestArchive(
            files: [
                "cards1.json": paymentCardsJson1,
                "cards2.JSON": paymentCardsJson2, // uppercase extension
                "other.json": nonPaymentJson
            ]
        )

        let contents = try reader.readContents(from: archiveURL, featureFlagger: mockFeatureFlagger)

        XCTAssertEqual(contents.creditCards.count, 2)
        XCTAssertTrue(contents.creditCards.contains(paymentCardsJson1))
        XCTAssertTrue(contents.creditCards.contains(paymentCardsJson2))
    }

    func testWhenArchiveIsNotZipFileThenThrowsError() throws {
        let invalidArchiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.zip")
        try Data("not a zip file".utf8).write(to: invalidArchiveURL)

        XCTAssertThrowsError(try reader.readContents(from: invalidArchiveURL, featureFlagger: mockFeatureFlagger))
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
