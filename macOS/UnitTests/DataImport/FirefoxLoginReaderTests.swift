//
//  FirefoxLoginReaderTests.swift
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
@testable import DuckDuckGo_Privacy_Browser
import BrowserServicesKit

class FirefoxLoginReaderTests: XCTestCase {

    private let rootDirectoryName = UUID().uuidString

    func testWhenImportingFirefox46LoginsWithNoPrimaryPassword_ThenImportSucceeds() throws {
        let database = resourcesURLWithoutPassword().appendingPathComponent("key3-firefox46.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins-firefox46.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key3.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(logins) = result {
            XCTAssertEqual(logins.count, 4)
        } else {
            XCTFail("Failed to decrypt Firefox logins")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithNoPrimaryPassword_ThenImportSucceeds() throws {
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(logins) = result {
            XCTAssertEqual(logins, [ImportedLoginCredential(url: "example.com", username: "testusername", password: "testpassword")])
        } else {
            XCTFail("Failed to decrypt Firefox logins")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithPrimaryPassword_AndNoPrimaryPasswordIsProvided_ThenImportFails() throws {
        let database = resourcesURLWithPassword().appendingPathComponent("key4-encrypted.db")
        let logins = resourcesURLWithPassword().appendingPathComponent("logins-encrypted.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        switch result {
        case .failure(let error as FirefoxLoginReader.ImportError):
            XCTAssertEqual(error.type, .requiresPrimaryPassword)
        default:
            XCTFail("Received unexpected \(result)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithPrimaryPassword_AndPrimaryPasswordIsProvided_ThenImportSucceeds() throws {
        let database = resourcesURLWithPassword().appendingPathComponent("key4-encrypted.db")
        let logins = resourcesURLWithPassword().appendingPathComponent("logins-encrypted.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "testpassword")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(logins) = result {
            XCTAssertEqual(logins, [ImportedLoginCredential(url: "example.com", username: "testusername", password: "testpassword")])
        } else {
            XCTFail("Failed to decrypt Firefox logins")
        }
    }

    func testWhenImportingLoginsFromADirectory_AndNoMatchingFilesAreFound_ThenImportFails() throws {
        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("unrelated-file", contents: .string(""))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        switch result {
        case .failure(let error as FirefoxLoginReader.ImportError):
            XCTAssertEqual(error.type, .couldNotFindKeyDB)
        default:
            XCTFail("Received unexpected \(result)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingFirefox70LoginsWithNoPrimaryPassword_ThenImportSucceeds() throws {
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4-firefox70.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins-firefox70.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(logins) = result {
            XCTAssertEqual(logins, [ImportedLoginCredential(url: "www.example.com", username: "test", password: "test")])
        } else {
            XCTFail("Failed to decrypt Firefox logins")
        }
    }

    func testWhenImportingFirefox70LoginsWithPrimaryPassword_AndPrimaryPasswordIsProvided_ThenImportSucceeds() throws {
        let database = resourcesURLWithPassword().appendingPathComponent("key4-firefox70.db")
        let logins = resourcesURLWithPassword().appendingPathComponent("logins-firefox70.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "test")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(logins) = result {
            XCTAssertEqual(logins, [ImportedLoginCredential(url: "www.example.com", username: "test", password: "test")])
        } else {
            XCTFail("Failed to decrypt Firefox logins")
        }
    }

    func testWhenImportingFirefox70LoginsWithPrimaryPassword_AndNoPrimaryPasswordIsProvided_ThenImportFails() throws {
        let database = resourcesURLWithPassword().appendingPathComponent("key4-firefox70.db")
        let logins = resourcesURLWithPassword().appendingPathComponent("logins-firefox70.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        switch result {
        case .failure(let error as FirefoxLoginReader.ImportError):
            XCTAssertEqual(error.type, .requiresPrimaryPassword)
        default:
            XCTFail("Received unexpected \(result)")
        }
    }

    func testWhenImportingFirefox84LoginsWithNoPrimaryPassword_ThenImportSucceeds() throws {
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4-firefox84.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins-firefox84.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(logins) = result {
            XCTAssertEqual(logins, [ImportedLoginCredential(url: "www.example.com", username: "test", password: "test")])
        } else {
            XCTFail("Failed to decrypt Firefox logins")
        }
    }

    func testWhenImportingFirefox84LoginsWithPrimaryPassword_AndPrimaryPasswordIsProvided_ThenImportSucceeds() throws {
        let database = resourcesURLWithPassword().appendingPathComponent("key4-firefox84.db")
        let logins = resourcesURLWithPassword().appendingPathComponent("logins-firefox84.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "test")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(logins) = result {
            XCTAssertEqual(logins, [ImportedLoginCredential(url: "www.example.com", username: "test", password: "test")])
        } else {
            XCTFail("Failed to decrypt Firefox logins")
        }
    }

    func testWhenImportingFirefox84LoginsWithPrimaryPassword_AndNoPrimaryPasswordIsProvided_ThenImportFails() throws {
        let database = resourcesURLWithPassword().appendingPathComponent("key4-firefox84.db")
        let logins = resourcesURLWithPassword().appendingPathComponent("logins-firefox84.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        switch result {
        case .failure(let error as FirefoxLoginReader.ImportError):
            XCTAssertEqual(error.type, .requiresPrimaryPassword)
        default:
            XCTFail("Received unexpected \(result)")
        }
    }

    func testWhenImportingLogins_AndNoKeysDBExists_ThenImportFailsWithNoDBError() throws {
        // Given
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)

        // When
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        // Then
        XCTAssertEqual(result, .failure(FirefoxLoginReader.ImportError(type: .couldNotFindKeyDB, underlyingError: nil)))
    }

    // MARK: - Deleted Entries Tests

    func testWhenImportingLoginsWithDeletedEntries_ThenImportSucceedsAndFiltersDeletedEntries() throws {
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins-with-deleted-entries.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        // Should succeed and import only the 1 active entry, filtering out the 2 deleted ones
        if case let .success(importedLogins) = result {
            XCTAssertEqual(importedLogins.count, 1)

            // Verify the imported login is the expected one (not the deleted entries)
            XCTAssertEqual(importedLogins.first?.url, "example.com")
            XCTAssertEqual(importedLogins.first?.username, "testusername")
            XCTAssertEqual(importedLogins.first?.password, "testpassword")
        } else {
            XCTFail("Failed to decrypt Firefox logins with deleted entries: \(result)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithDeletedEntriesAndPrimaryPassword_ThenImportSucceedsAndFiltersDeletedEntries() throws {
        let database = resourcesURLWithPassword().appendingPathComponent("key4-encrypted.db")
        let logins = resourcesURLWithPassword().appendingPathComponent("logins-with-deleted-entries.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL, primaryPassword: "testpassword")
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        // Should succeed and import only the 1 active entry
        if case let .success(importedLogins) = result {
            XCTAssertEqual(importedLogins.count, 1)

            XCTAssertEqual(importedLogins.first?.url, "example.com")
        } else {
            XCTFail("Failed to decrypt Firefox logins with deleted entries and primary password: \(result)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithAllDeletedEntries_ThenImportSucceedsWithEmptyResult() throws {
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins-all-deleted.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        // Should succeed but return empty result since all entries are deleted
        if case let .success(importedLogins) = result {
            XCTAssertEqual(importedLogins.count, 0)
        } else {
            XCTFail("Failed to handle all-deleted entries case: \(result)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithMalformedEntries_ThenImportSucceedsAndFiltersInvalidEntries() throws {
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins-with-malformed-entries.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        // Should succeed and import only the 1 valid entry, filtering out malformed ones
        if case let .success(importedLogins) = result {
            XCTAssertEqual(importedLogins.count, 1)
            XCTAssertEqual(importedLogins.first?.url, "example.com")
            XCTAssertEqual(importedLogins.first?.username, "testusername")
            XCTAssertEqual(importedLogins.first?.password, "testpassword")
        } else {
            XCTFail("Failed to handle malformed entries case: \(result)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithOnlyDeletedEntriesAtStart_ThenImportSucceeds() throws {
        // This test specifically verifies the original bug case where deleted entries at index 0 
        // would cause immediate decode failure
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins-with-deleted-entries.json")

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        // Before the fix, this would fail with DecodingError.keyNotFound for hostname
        // After the fix, it should succeed and return the active logins
        switch result {
        case .success(let importedLogins):
            XCTAssertEqual(importedLogins.count, 1)
            // Verify we got the active entry, not the deleted ones at indices 0 and 1
            XCTAssertEqual(importedLogins.first?.url, "example.com")
        case .failure(let error):
            XCTFail("Import should succeed with deleted entries at start, but failed with: \(error)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    func testWhenImportingLoginsWithFirefoxSyncEntries_ThenFiltersFirefoxAccountsAndDeletedEntries() throws {
        // Test that both Firefox sync entries and deleted entries are properly filtered
        let database = resourcesURLWithoutPassword().appendingPathComponent("key4.db")
        let logins = resourcesURLWithoutPassword().appendingPathComponent("logins.json") // This file has FirefoxAccounts entry

        let structure = FileSystem(rootDirectoryName: rootDirectoryName) {
            File("key4.db", contents: .copy(database))
            File("logins.json", contents: .copy(logins))
        }

        try structure.writeToTemporaryDirectory()
        let profileDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName)

        let firefoxLoginReader = FirefoxLoginReader(firefoxProfileURL: profileDirectoryURL)
        let result = firefoxLoginReader.readLogins(dataFormat: nil)

        if case let .success(importedLogins) = result {
            // Should filter out chrome://FirefoxAccounts entries
            XCTAssertTrue(importedLogins.compactMap { $0.url }.filter { $0.contains("chrome://FirefoxAccounts") }.isEmpty)
            // Should only import the example.com entry
            XCTAssertEqual(importedLogins.count, 1)
            XCTAssertEqual(importedLogins.first?.url, "example.com")
        } else {
            XCTFail("Failed to import logins with Firefox sync filtering: \(result)")
        }

        try structure.removeCreatedFileSystemStructure()
    }

    private func resourcesURLWithPassword() -> URL {
        let bundle = Bundle(for: FirefoxLoginReaderTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData/Primary Password")
    }

    private func resourcesURLWithoutPassword() -> URL {
        let bundle = Bundle(for: FirefoxLoginReaderTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData/No Primary Password")
    }

}
