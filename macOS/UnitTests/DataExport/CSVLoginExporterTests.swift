//
//  CSVLoginExporterTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Foundation
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class CSVLoginExporterTests: XCTestCase {

    func testWhenExportingLogins_ThenLoginsArePersistedToDisk() throws {
        let mockFileStore = FileStoreMock()
        let vault = try MockSecureVaultFactory.makeVault(reporter: nil)

        vault.addWebsiteCredentials(identifiers: [1])

        let exporter = CSVLoginExporter(secureVault: vault, fileStore: mockFileStore)

        let mockURL = URL(fileURLWithPath: "mock-url")
        try? exporter.exportVaultLogins(to: mockURL)

        let data = mockFileStore.loadData(at: mockURL)
        XCTAssertNotNil(data)

        let expectedHeader = "\"title\",\"url\",\"username\",\"password\",\"notes\"\n"
        let expectedRow = "\"title-1\",\"domain-1\",\"user-1\",\"password\"\"containing\"\"quotes\",\"\""
        XCTAssertEqual(data, (expectedHeader + expectedRow).data(using: .utf8)!)
    }

    // #1 — A login whose title (or any non-password field) contains a double quote must survive a
    // round-trip through the CSV importer. Today only the password field is quote-escaped, so the raw
    // quote breaks CSV parsing and the fields shift on re-import — silently corrupting the credential.
    func testWhenLoginTitleContainsQuotes_ThenExportedCSVRoundTripsWithoutCorruption() throws {
        let mockFileStore = FileStoreMock()
        let vault = try MockSecureVaultFactory.makeVault(reporter: nil)

        let account = SecureVaultModels.WebsiteAccount(id: "1",
                                                       title: "My \"work\" account",
                                                       username: "user@example.com",
                                                       domain: "example.com")
        let credential = SecureVaultModels.WebsiteCredentials(account: account,
                                                              password: "p4ssw0rd".data(using: .utf8)!)
        vault.storedAccounts = [account]
        vault.storedCredentials = [1: credential]

        let exporter = CSVLoginExporter(secureVault: vault, fileStore: mockFileStore)
        let mockURL = URL(fileURLWithPath: "mock-url")
        try exporter.exportVaultLogins(to: mockURL)

        let data = try XCTUnwrap(mockFileStore.loadData(at: mockURL))
        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Re-import exactly the way DuckDuckGo's CSV importer parses the file.
        let rows = try CSVParser().parse(string: csv)
        let dataRows = Array(rows.dropFirst()) // drop the header row

        XCTAssertEqual(dataRows.count, 1, "Expected a single credential row, got: \(dataRows)")
        let row = try XCTUnwrap(dataRows.first)
        XCTAssertEqual(row.count, 5, "Unescaped quote in the title shifted the CSV columns: \(row)")
        XCTAssertEqual(row.first, "My \"work\" account", "Title was corrupted on re-import")
        let passwordColumn = row.indices.contains(3) ? row[3] : nil
        XCTAssertEqual(passwordColumn, "p4ssw0rd", "Password landed in the wrong column due to the unescaped title quote")
    }

    // #2 — When the file write fails, the export must surface the failure. Today the Bool result of
    // `persist` is discarded, so a failed write (disk full, permission denied) reports success and the
    // user is left believing their passwords are backed up when no file exists.
    func testWhenFileStorePersistFails_ThenExportThrows() throws {
        let mockFileStore = FileStoreMock()
        mockFileStore.failWithError = NSError(domain: "CSVLoginExporterTests", code: 1)

        let vault = try MockSecureVaultFactory.makeVault(reporter: nil)
        vault.addWebsiteCredentials(identifiers: [1])

        let exporter = CSVLoginExporter(secureVault: vault, fileStore: mockFileStore)

        XCTAssertThrowsError(try exporter.exportVaultLogins(to: URL(fileURLWithPath: "mock-url")),
                             "Export must throw when the file write fails")
    }
}
