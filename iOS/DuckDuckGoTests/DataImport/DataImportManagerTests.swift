//
//  DataImportManagerTests.swift
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
import BrowserServicesKit
import Common
import Persistence
import SecureStorage

final class DataImportManagerTests: XCTestCase {

    private var dataImportManager: DataImportManager!
    private var loginImporter: MockLoginImporter!
    private var creditCardImporter: MockCreditCardImporter!
    private var reporter: SecureVaultReporting!
    private var mockDatabase: CoreDataDatabase!
    private var tld: TLD!
    private var htmlLoader: HtmlTestDataLoader!
    private var vault = (try? MockSecureVaultFactory.makeVault(reporter: nil))!

    override func setUpWithError() throws {
        try super.setUpWithError()

        loginImporter = MockLoginImporter()
        creditCardImporter = MockCreditCardImporter()
        reporter = MockSecureVaultReporting()
        mockDatabase = MockBookmarksDatabase.make()
        tld = TLD()
        htmlLoader = HtmlTestDataLoader()

        dataImportManager = DataImportManager(
            loginImporter: loginImporter,
            creditCardImporter: creditCardImporter,
            vault: vault,
            reporter: reporter,
            bookmarksDatabase: mockDatabase,
            favoritesDisplayMode: .displayNative(.mobile),
            tld: tld
        )
    }

    override func tearDownWithError() throws {
        dataImportManager = nil
        loginImporter = nil
        creditCardImporter = nil
        reporter = nil
        mockDatabase = nil
        tld = nil
        htmlLoader = nil

        try super.tearDownWithError()
    }

    func testWhenValidThenFileTypeIdentifiersAreCorrectlyMapped() {
        let zipIdentifier = "public.zip-archive"
        let csvIdentifier = "public.comma-separated-values-text"
        let htmlIdentifier = "public.html"
        let invalidIdentifier = "invalid.type"

        XCTAssertEqual(DataImportManager.FileType(typeIdentifier: zipIdentifier), .zip)
        XCTAssertEqual(DataImportManager.FileType(typeIdentifier: csvIdentifier), .csv)
        XCTAssertEqual(DataImportManager.FileType(typeIdentifier: htmlIdentifier), .html)
        XCTAssertNil(DataImportManager.FileType(typeIdentifier: invalidIdentifier))
    }

    // MARK: - CSV Import Tests

    func testWhenImportingCSVFileThenPasswordsSuccessfullyImported() async throws {
        let testURL = Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv")!

        let expectedSummary = DataImport.DataTypeSummary(successful: 11, duplicate: 0, failed: 0)

        let result = try await dataImportManager.importFile(at: testURL, for: .csv)
        let summary = try? result?[.passwords]?.get()

        XCTAssertEqual(summary, expectedSummary)
    }

    // MARK: - HTML Import Tests

    func testWhenImportHtmlFileThenBookmarksSuccessfullyImport() async throws {
        let testURL = Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/bookmarks/bookmarks_safari", withExtension: "html")!

        let expectedSummary = DataImport.DataTypeSummary(successful: 29, duplicate: 0, failed: 0)

        let result = try await dataImportManager.importFile(at: testURL, for: .html)
        let summary = try? result?[.bookmarks]?.get()

        XCTAssertEqual(summary, expectedSummary)
    }

    // MARK: - JSON Import Tests

    func testWhenImportingJSONFileThenCreditCardsSuccessfullyImported() async throws {
        let testURL = Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/creditcards/payment_cards", withExtension: "json")!

        let expectedSummary = DataImport.DataTypeSummary(successful: 3, duplicate: 0, failed: 0)

        let result = try await dataImportManager.importFile(at: testURL, for: .json)
        let summary = try? result?[.creditCards]?.get()

        XCTAssertEqual(summary, expectedSummary)
    }

    // MARK: - ZIP Import Tests

    func testWhenImportZipArchiveWithAllThreeDataTypesThenAllAreImported() async throws {
        let contents = ImportArchiveContents(
            passwords: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv")!)],
            bookmarks: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/bookmarks/bookmarks_safari", withExtension: "html")!)],
            creditCards: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/creditcards/payment_cards", withExtension: "json")!)]
        )

        let result = await dataImportManager.importZipArchive(from: contents, for: [.passwords, .bookmarks, .creditCards])

        XCTAssertNotNil(result[.passwords])
        XCTAssertNotNil(result[.bookmarks])
        XCTAssertNotNil(result[.creditCards])

        let passwordsSummary = try result[.passwords]?.get()
        let bookmarksSummary = try result[.bookmarks]?.get()
        let creditCardsSummary = try result[.creditCards]?.get()

        XCTAssertEqual(passwordsSummary?.successful, 11)
        XCTAssertEqual(bookmarksSummary?.successful, 29)
        XCTAssertEqual(creditCardsSummary?.successful, 3)
    }

    func testWhenImportZipArchiveWithBothPasswordsAndBookmarksThenBothAreImported() async throws {
        let contents = ImportArchiveContents(
            passwords: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv")!)],
            bookmarks: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/bookmarks/bookmarks_safari", withExtension: "html")!)],
            creditCards: []
        )

        let result = await dataImportManager.importZipArchive(from: contents, for: [.passwords, .bookmarks])

        XCTAssertNotNil(result[.passwords])
        XCTAssertNotNil(result[.bookmarks])
        XCTAssertNil(result[.creditCards])

        let passwordsSummary = try result[.passwords]?.get()
        let bookmarksSummary = try result[.bookmarks]?.get()

        XCTAssertEqual(passwordsSummary?.successful, 11)
        XCTAssertEqual(bookmarksSummary?.successful, 29)
    }

    func testWhenImportZipArchiveWithOnlyPasswordsThenPasswordsAreImported() async throws {
        let contents = ImportArchiveContents(
            passwords: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv")!)],
            bookmarks: [],
            creditCards: []
        )

        let result = await dataImportManager.importZipArchive(from: contents, for: [.passwords])

        XCTAssertNotNil(result[.passwords])
        XCTAssertNil(result[.bookmarks])
        XCTAssertNil(result[.creditCards])

        let passwordsSummary = try result[.passwords]?.get()
        XCTAssertEqual(passwordsSummary?.successful, 11)
    }

    func testWhenImportZipArchiveWithOnlyBookmarksThenBookmarksAreImported() async throws {
        let contents = ImportArchiveContents(
            passwords: [],
            bookmarks: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/bookmarks/bookmarks_safari", withExtension: "html")!)],
            creditCards: []
        )

        let result = await dataImportManager.importZipArchive(from: contents, for: [.bookmarks])

        XCTAssertNil(result[.passwords])
        XCTAssertNotNil(result[.bookmarks])
        XCTAssertNil(result[.creditCards])

        let bookmarksSummary = try result[.bookmarks]?.get()
        XCTAssertEqual(bookmarksSummary?.successful, 29)
    }

    func testWhenImportZipArchiveWithOnlyCreditCardsThenCreditCardsAreImported() async throws {
        let contents = ImportArchiveContents(
            passwords: [],
            bookmarks: [],
            creditCards: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/creditcards/payment_cards", withExtension: "json")!)]
        )

        let result = await dataImportManager.importZipArchive(from: contents, for: [.creditCards])

        XCTAssertNil(result[.passwords])
        XCTAssertNil(result[.bookmarks])
        XCTAssertNotNil(result[.creditCards])

        let creditCardsSummary = try result[.creditCards]?.get()
        XCTAssertEqual(creditCardsSummary?.successful, 3)
    }

    func testWhenImportZipArchiveWithPasswordsAndCreditCardsThenBothAreImported() async throws {
        let contents = ImportArchiveContents(
            passwords: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv")!)],
            bookmarks: [],
            creditCards: [try String(contentsOf: Bundle(for: DataImportManagerTests.self)
                .url(forResource: "MockFiles/creditcards/payment_cards", withExtension: "json")!)]
        )

        let result = await dataImportManager.importZipArchive(from: contents, for: [.passwords, .creditCards])

        XCTAssertNotNil(result[.passwords])
        XCTAssertNil(result[.bookmarks])
        XCTAssertNotNil(result[.creditCards])

        let passwordsSummary = try result[.passwords]?.get()
        let creditCardsSummary = try result[.creditCards]?.get()

        XCTAssertEqual(passwordsSummary?.successful, 11)
        XCTAssertEqual(creditCardsSummary?.successful, 3)
    }

    func testImportZipArchiveIsEmptyThenNoDataIsImported() async throws {
        let contents = ImportArchiveContents(passwords: [], bookmarks: [], creditCards: [])

        let result = await dataImportManager.importZipArchive(from: contents, for: [.passwords, .bookmarks, .creditCards])

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Preview Tests

    func testWhenImportZipArchiveWithAllThreeDataTypesThePreviewCountsAreCorrect() throws {
        let passwordsURL = try XCTUnwrap(Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv"))
        let bookmarksURL = try XCTUnwrap(Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/bookmarks/bookmarks_safari", withExtension: "html"))
        let creditCardsURL = try XCTUnwrap(Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/creditcards/payment_cards", withExtension: "json"))

        let contents = ImportArchiveContents(
            passwords: [try String(contentsOf: passwordsURL)],
            bookmarks: [try String(contentsOf: bookmarksURL)],
            creditCards: [try String(contentsOf: creditCardsURL)]
        )

        let previews = DataImportManager.preview(contents: contents, tld: tld)

        XCTAssertEqual(previews.count, 3)
        XCTAssertEqual(previews.first(where: { $0.type == .passwords })?.count, 11)
        XCTAssertEqual(previews.first(where: { $0.type == .bookmarks })?.count, 29)
        XCTAssertNotNil(previews.first(where: { $0.type == .creditCards }))
    }

    func testWhenImportZipArchiveWithBothPasswordsAndBookmarksThePreviewCountsAreCorrect() throws {
        let passwordsURL = try XCTUnwrap(Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/passwords/passwords", withExtension: "csv"))
        let bookmarksURL = try XCTUnwrap(Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/bookmarks/bookmarks_safari", withExtension: "html"))

        let contents = ImportArchiveContents(
            passwords: [try String(contentsOf: passwordsURL)],
            bookmarks: [try String(contentsOf: bookmarksURL)],
            creditCards: []
        )

        let previews = DataImportManager.preview(contents: contents, tld: tld)

        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(previews.first(where: { $0.type == .passwords })?.count, 11)
        XCTAssertEqual(previews.first(where: { $0.type == .bookmarks })?.count, 29)
    }

    func testImportZipArchiveIsEmptyThenPreviewIsEmpty() {
        let contents = ImportArchiveContents(passwords: [], bookmarks: [], creditCards: [])

        let previews = DataImportManager.preview(contents: contents, tld: tld)

        XCTAssertTrue(previews.isEmpty)
    }

    func testWhenPreviewWithOnlyCreditCardsThenCountIsCorrect() throws {
        let creditCardsURL = try XCTUnwrap(Bundle(for: DataImportManagerTests.self)
            .url(forResource: "MockFiles/creditcards/payment_cards", withExtension: "json"))

        let contents = ImportArchiveContents(
            passwords: [],
            bookmarks: [],
            creditCards: [try String(contentsOf: creditCardsURL)]
        )

        let previews = DataImportManager.preview(contents: contents, tld: tld)

        XCTAssertEqual(previews.count, 1)
        XCTAssertNotNil(previews.first(where: { $0.type == .creditCards }))
    }
}

// MARK: - Mock Classes

private class MockLoginImporter: LoginImporter {
    var importedLogins: DataImportSummary?

    func importLogins(_ logins: [BrowserServicesKit.ImportedLoginCredential], reporter: SecureVaultReporting, progressCallback: @escaping (Int) throws -> Void) throws -> DataImport.DataTypeSummary {
        let summary = DataImport.DataTypeSummary(successful: logins.count, duplicate: 0, failed: 0)

        self.importedLogins = [.passwords: .success(summary)]
        return summary
    }
}

private class MockCreditCardImporter: CreditCardImporter {
    var importedCreditCards: DataImportSummary?

    func importCreditCards(_ cards: [BrowserServicesKit.ImportedCreditCard], vault: (any AutofillSecureVault)?, completion: @escaping (Int) throws -> Void) throws -> DataImport.DataTypeSummary {
        let summary = DataImport.DataTypeSummary(successful: cards.count, duplicate: 0, failed: 0)

        self.importedCreditCards = [.creditCards: .success(summary)]
        return summary
    }
}
