//
//  CSVImporterTests.swift
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

import Foundation
import XCTest
@testable import BrowserServicesKit
import SecureStorage
import Common

class CSVImporterTests: XCTestCase {

    let temporaryFileCreator = TemporaryFileCreator()
    let tld: TLD = TLD()

    override func tearDown() {
        super.tearDown()
        temporaryFileCreator.deleteCreatedTemporaryFiles()
    }

    func testWhenImportingCSVFileWithHeader_ThenHeaderRowIsExcluded() {
        let csvFileContents = """
        title,url,username,password
        Some Title,duck.com,username,p4ssw0rd
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins, [ImportedLoginCredential(title: "Some Title", url: "duck.com", eTldPlusOne: "duck.com", username: "username", password: "p4ssw0rd")])
    }

    func testWhenImportingCSVFileWithHeader_AndHeaderHasBitwardenFormat_ThenHeaderRowIsExcluded() {
        let csvFileContents = """
        name,login_uri,login_username,login_password
        Some Title,duck.com,username,p4ssw0rd
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins, [ImportedLoginCredential(title: "Some Title", url: "duck.com", eTldPlusOne: "duck.com", username: "username", password: "p4ssw0rd")])
    }

    func testWhenImportingCSVFileWithHeader_ThenHeaderColumnPositionsAreRespected() {
        let csvFileContents = """
        Password,Title,Username,Url
        p4ssw0rd,"Some Title",username,duck.com
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins, [ImportedLoginCredential(title: "Some Title", url: "duck.com", eTldPlusOne: "duck.com", username: "username", password: "p4ssw0rd")])
    }

    func testWhenImportingCSVFileWithoutHeader_ThenNoRowsAreExcluded() {
        let csvFileContents = """
        Some Title,duck.com,username,p4ssw0rd
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins, [ImportedLoginCredential(title: "Some Title", url: "duck.com", eTldPlusOne: "duck.com", username: "username", password: "p4ssw0rd")])
    }

    func testWhenImportingCSVDataFromTheFileSystem_AndNoTitleIsIncluded_ThenLoginCredentialsAreImported() async {
        let mockLoginImporter = MockLoginImporter()
        let file = "https://example.com/,username,password"
        let savedFileURL = temporaryFileCreator.persist(fileContents: file.data(using: .utf8)!, named: "test.csv")!
        let csvImporter = CSVImporter(fileURL: savedFileURL, loginImporter: mockLoginImporter, defaultColumnPositions: nil, reporter: MockSecureVaultReporting(), tld: tld)

        let result = await csvImporter.importData(types: [.passwords]).task.value

        XCTAssertEqual(result, [.passwords: .success(.init(successful: 1, duplicate: 0, failed: 0))])
    }

    func testWhenImportingCSVDataFromTheFileSystem_AndTitleIsIncluded_ThenLoginCredentialsAreImported() async {
        let mockLoginImporter = MockLoginImporter()
        let file = "title,https://example.com/,username,password"
        let savedFileURL = temporaryFileCreator.persist(fileContents: file.data(using: .utf8)!, named: "test.csv")!
        let csvImporter = CSVImporter(fileURL: savedFileURL, loginImporter: mockLoginImporter, defaultColumnPositions: nil, reporter: MockSecureVaultReporting(), tld: tld)

        let result = await csvImporter.importData(types: [.passwords]).task.value

        XCTAssertEqual(result, [.passwords: .success(.init(successful: 1, duplicate: 0, failed: 0))])
    }

    func testWhenInferringColumnPostions_AndColumnsAreValid_AndTitleIsIncluded_ThenPositionsAreCalculated() {
        let csvValues = ["url", "username", "password", "title"]
        let inferred = CSVImporter.ColumnPositions(csvValues: csvValues)

        XCTAssertEqual(inferred?.urlIndex, 0)
        XCTAssertEqual(inferred?.usernameIndex, 1)
        XCTAssertEqual(inferred?.passwordIndex, 2)
        XCTAssertEqual(inferred?.titleIndex, 3)
    }

    func testWhenInferringColumnPostions_AndColumnsAreValid_AndTitleIsNotIncluded_ThenPositionsAreCalculated() {
        let csvValues = ["url", "username", "password"]
        let inferred = CSVImporter.ColumnPositions(csvValues: csvValues)

        XCTAssertEqual(inferred?.urlIndex, 0)
        XCTAssertEqual(inferred?.usernameIndex, 1)
        XCTAssertEqual(inferred?.passwordIndex, 2)
        XCTAssertNil(inferred?.titleIndex)
    }

    func testWhenInferringColumnPostions_AndColumnsAreInvalidThenPositionsAreCalculated() {
        let csvValues = ["url", "username", "title"] // `password` is required, this test verifies that the inference fails when it's missing
        let inferred = CSVImporter.ColumnPositions(csvValues: csvValues)

        XCTAssertNil(inferred)
    }

    // MARK: - Safari Title Format Tests

    func testWhenTitleMatchesSafariFormat_ThenFormatIsDetected() {
        let csvFileContents = """
        title,url,username,password
        example.com (user1),example.com,user1,pass1
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 1)
        XCTAssertEqual(logins?.first?.title, "example.com (user1)")
    }

    func testWhenTitleDoesNotMatchSafariFormat_ThenFormatIsNotDetected() {
        let csvFileContents = """
        title,url,username,password
        example.com user1,example.com,user1,pass1
        example.com [user1],example.com,user1,pass1
        example.com (user1,example.com,user1,pass1
        example.com (wrong_user),example.com,user1,pass1
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 4)
    }

    func testWhenMultipleSafariTitleFormats_ThenAllFormatsAreHandled() {
        let csvFileContents = """
        title,url,username,password
        example.com (user1),example.com,user1,pass1
        sub.example.com (user1),sub.example.com,user1,pass1
        different.com (user2),different.com,user2,pass2
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 2)  // The first two should be considered duplicates
    }

    func testWhenSafariTitleFormatMixedWithRegularTitles_ThenDeduplicationHandlesBothFormats() {
        let csvFileContents = """
        title,url,username,password
        example.com (user1),example.com,user1,pass1
        Regular Title,example.com,user1,pass1
        example.com (user2),example.com,user2,pass2
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 3)  // No deduplication as titles don't match
    }

    // MARK: - Deduplication Tests

    func testWhenDuplicateCredentials_WithBaseDomainAndSubdomain_ThenBaseDomainIsPreferred() {
        let csvFileContents = """
        title,url,username,password
        Same Title,example.com,user1,pass1
        Same Title,sub.example.com,user1,pass1
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 1)
        XCTAssertEqual(logins?.first?.url, "example.com")
    }

    func testWhenDuplicateCredentials_WithWWWAndOtherSubdomains_ThenWWWIsPreferred() {
        let csvFileContents = """
        title,url,username,password
        Same Title,www.example.com,user1,pass1
        Same Title,sub.example.com,user1,pass1
        Same Title,other.example.com,user1,pass1
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 1)
        XCTAssertEqual(logins?.first?.url, "www.example.com")
    }

    func testWhenDuplicateCredentials_WithOnlySubdomains_ThenShortestDomainIsPreferred() {
        let csvFileContents = """
        title,url,username,password
        Same Title,sub.example.com,user1,pass1
        Same Title,a.b.example.com,user1,pass1
        Same Title,x.sub.example.com,user1,pass1
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 1)
        XCTAssertEqual(logins?.first?.url, "sub.example.com")
    }

    func testWhenDuplicateCredentials_WithSafariFormatTitle_ThenDuplicatesAreRemoved() {
        let csvFileContents = """
        title,url,username,password
        example.com (user1),example.com,user1,pass1
        example.com (user1),sub.example.com,user1,pass1
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 1)
        XCTAssertEqual(logins?.first?.url, "example.com")
    }

    func testWhenDuplicateCredentials_WithDifferentNotes_ThenTreatedAsUnique() {
        let csvFileContents = """
        title,url,username,password,notes
        Title,example.com,user1,pass1,note1
        Title,example.com,user1,pass1,note2
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 2)
    }

    func testWhenCompletelyIdenticalCredentials_ThenOnlyOneIsKept() {
        let csvFileContents = """
        title,url,username,password,notes
        Title,example.com,user1,pass1,note1
        Title,example.com,user1,pass1,note1
        """

        let logins = CSVImporter.extractLogins(from: csvFileContents, tld: tld)
        XCTAssertEqual(logins?.count, 1)
    }
}

extension CSVImporter.ColumnPositions {

    init?(csvValues: [String]) {
        self.init(csv: [csvValues, Array(repeating: "", count: csvValues.count)])
    }

}

private class MockSecureVaultReporting: SecureVaultReporting {
    func secureVaultError(_ error: SecureStorage.SecureStorageError) {}
}
