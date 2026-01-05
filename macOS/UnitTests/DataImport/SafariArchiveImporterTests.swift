//
//  SafariArchiveImporterTests.swift
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

import Bookmarks
import BrowserServicesKit
import Combine
import Common
import PrivacyConfig
import SecureStorage
import XCTest
import ZIPFoundation
@testable import DuckDuckGo_Privacy_Browser

final class SafariArchiveImporterTests: XCTestCase {

    private var tempDirectory: URL!
    private var loginImporter: MockLoginImporter!
    private var bookmarkImporter: MockBookmarkImporter!
    private var creditCardImporter: SafariArchiveImporterTestsCreditCardImporter!
    private var faviconManager: FaviconManagerMock!
    private var featureFlagger: MockFeatureFlagger!
    private var secureVaultReporter: SafariArchiveImporterTestsSecureVaultReporter!
    private var vault: (any AutofillSecureVault)!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        loginImporter = MockLoginImporter()

        bookmarkImporter = MockBookmarkImporter { _, _, _, _ in
            BookmarksImportSummary(successful: 1, duplicates: 0, failed: 0)
        }

        creditCardImporter = SafariArchiveImporterTestsCreditCardImporter()
        faviconManager = FaviconManagerMock()
        featureFlagger = MockFeatureFlagger()
        secureVaultReporter = SafariArchiveImporterTestsSecureVaultReporter()
        vault = try MockSecureVaultFactory.makeVault(reporter: nil)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        loginImporter = nil
        bookmarkImporter = nil
        creditCardImporter = nil
        faviconManager = nil
        featureFlagger = nil
        secureVaultReporter = nil
        vault = nil
        try super.tearDownWithError()
    }

    func testWhenFileIsCSVThenImportableTypesReturnPasswords() throws {
        let url = try writeTempFile(named: "passwords.csv", contents: "title,url,username,password\nExample,duck.com,user,pass")

        let importer = makeImporter(fileURL: url)

        XCTAssertEqual(importer.importableTypes, [.passwords])
    }

    func testWhenFileIsHTMLThenImportableTypesReturnBookmarks() throws {
        let url = try copyFixture(named: "bookmarks_safari.html", as: "bookmarks.html")

        let importer = makeImporter(fileURL: url)

        XCTAssertEqual(importer.importableTypes, [.bookmarks])
    }

    func testWhenFileIsJSONThenImportableTypesReturnCreditCards() throws {
        let url = try writeTempFile(named: "payment_cards.json", contents: validCreditCardsJSON)

        let importer = makeImporter(fileURL: url)

        XCTAssertEqual(importer.importableTypes, [.creditCards])
    }

    func testWhenImportingCSVFileThenPasswordsAreImported() async throws {
        let url = try writeTempFile(named: "passwords.csv", contents: "title,url,username,password\nExample,duck.com,user,pass")
        let importer = makeImporter(fileURL: url)

        let summary = await importer.importData(types: [.passwords]).task.value

        guard case .success(let passwordsSummary)? = summary[.passwords] else {
            return XCTFail("Expected passwords summary")
        }
        XCTAssertEqual(passwordsSummary.successful, 1)
    }

    func testWhenImportingHTMLFileThenBookmarksAreImported() async throws {
        let url = try copyFixture(named: "bookmarks_safari.html", as: "bookmarks.html")
        let importer = makeImporter(fileURL: url)

        let summary = await importer.importData(types: [.bookmarks]).task.value

        guard case .success(let bookmarksSummary)? = summary[.bookmarks] else {
            return XCTFail("Expected bookmarks summary")
        }
        XCTAssertEqual(bookmarksSummary.successful, 1)
    }

    func testWhenImportingJSONFileThenCreditCardsAreImported() async throws {
        let url = try writeTempFile(named: "payment_cards.json", contents: validCreditCardsJSON)
        let importer = makeImporter(fileURL: url)

        let summary = await importer.importData(types: [.creditCards]).task.value

        guard case .success(let creditCardsSummary)? = summary[.creditCards] else {
            return XCTFail("Expected credit cards summary")
        }

        XCTAssertEqual(creditCardsSummary.successful, 1)
        XCTAssertEqual(creditCardImporter.importedCardsCount, 1)
    }

    func testWhenImportingZipArchiveThenAllDataTypesAreImported() async throws {
        let bookmarkFixture = try copyFixture(named: "bookmarks_safari.html", as: "embedded_bookmarks.html")
        let zipURL = try createZipArchive(files: [
            "passwords.csv": "title,url,username,password\nExample,duck.com,user,pass",
            "nested/bookmarks.html": try Data(contentsOf: bookmarkFixture),
            "credit_cards/payment_cards.json": validCreditCardsJSON
        ])

        let importer = makeImporter(fileURL: zipURL)
        let summary = await importer.importData(types: [.passwords, .bookmarks, .creditCards]).task.value

        guard case .success(let passwords)? = summary[.passwords],
              case .success(let bookmarks)? = summary[.bookmarks],
              case .success(let cards)? = summary[.creditCards] else {
            return XCTFail("Expected summaries for all data types")
        }

        XCTAssertEqual(passwords.successful, 1)
        XCTAssertEqual(bookmarks.successful, 1)
        XCTAssertEqual(cards.successful, 1)
        XCTAssertEqual(creditCardImporter.importedCardsCount, 1)
    }

    // MARK: - Helpers

    private func makeImporter(fileURL: URL) -> SafariArchiveImporter {
        SafariArchiveImporter(archiveURL: fileURL,
                              bookmarkImporter: bookmarkImporter,
                              loginImporter: loginImporter,
                              creditCardImporter: creditCardImporter,
                              vault: vault,
                              faviconManager: faviconManager,
                              featureFlagger: featureFlagger,
                              secureVaultReporter: secureVaultReporter,
                              tld: TLD())
    }

    private func writeTempFile(named name: String, contents: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func copyFixture(named fixture: String, as outputName: String) throws -> URL {
        let bundle = Bundle(for: type(of: self))
        let sourceURL = bundle.resourceURL!
            .appendingPathComponent("DataImportResources/TestBookmarksData")
            .appendingPathComponent(fixture)

        let destinationURL = tempDirectory.appendingPathComponent(outputName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private var validCreditCardsJSON: String {
        """
        {
            "payment_cards": [{
                "card_number": "4111111111111111",
                "card_name": "Personal Visa",
                "cardholder_name": "John Doe",
                "card_expiration_month": 12,
                "card_expiration_year": 2025
            }]
        }
        """
    }

    private func createZipArchive(files: [String: Any]) throws -> URL {
        let archiveURL = tempDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)

        for (filename, content) in files {
            let data: Data
            if let stringContent = content as? String {
                data = Data(stringContent.utf8)
            } else if let contentData = content as? Data {
                data = contentData
            } else {
                continue
            }

            try archive.addEntry(with: filename,
                                 type: .file,
                                 uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate,
                                 provider: { position, size in
                let start = Int(position)
                let end = start + Int(size)
                return data.subdata(in: start..<end)
            })
        }

        return archiveURL
    }
}

// MARK: - Helpers

final private class SafariArchiveImporterTestsCreditCardImporter: CreditCardImporter {
    private(set) var importedCardsCount: Int = 0

    func importCreditCards(_ cards: [ImportedCreditCard],
                           vault: (any AutofillSecureVault)?,
                           completion: @escaping (Int) throws -> Void) throws -> DataImport.DataTypeSummary {
        importedCardsCount = cards.count
        try completion(cards.count)
        return DataImport.DataTypeSummary(successful: cards.count, duplicate: 0, failed: 0)
    }
}

final private class SafariArchiveImporterTestsSecureVaultReporter: SecureVaultReporting {
    func secureVaultError(_ error: SecureStorageError) {}
    func secureVaultKeyStoreEvent(_ event: SecureStorageKeyStoreEvent) {}
}
