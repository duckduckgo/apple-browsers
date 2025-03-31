//
//  AppGroupFileStorageManagerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit

final class AppGroupFileStorageManagerTests: XCTestCase {

    var mockFileManager: MockFileManager!
    var fileStorageManager: AppGroupFileStorageManager!

    override func setUp() {
        super.setUp()
        mockFileManager = MockFileManager()
        fileStorageManager = AppGroupFileStorageManager(fileManager: mockFileManager)
    }

    func testWhenMigrateDatabaseToSharedStorageIfNeeded_ThenMigratesDatabaseSuccessfully() throws {
        let originalURL = URL(fileURLWithPath: "/path/to/Vault.db")
        let sharedDatabaseURL = URL(fileURLWithPath: "/shared/path/Vault.db")

        mockFileManager.files.insert(originalURL)

        let resultURL = try fileStorageManager.migrateDatabaseToSharedStorageIfNeeded(from: originalURL, to: sharedDatabaseURL)

        XCTAssertEqual(resultURL, sharedDatabaseURL, "The shared database URL should be returned after migration.")
        XCTAssertTrue(mockFileManager.files.contains(sharedDatabaseURL), "Shared database should exist after migration.")
        XCTAssertTrue(mockFileManager.files.contains(sharedDatabaseURL), "The file should have been copied to the shared location.")
        XCTAssertFalse(mockFileManager.files.contains(originalURL), "The original file should have been deleted after a successful migration.")
    }

    func testWhenMigrateDatabaseToSharedStorageIfNeeded_ThenDoesNotMigrateIfSharedDatabaseExists() throws {
        let originalURL = URL(fileURLWithPath: "/path/to/Vault.db")
        let sharedDatabaseURL = URL(fileURLWithPath: "/shared/path/Vault.db")

        mockFileManager.files.insert(originalURL)
        mockFileManager.files.insert(sharedDatabaseURL)

        let resultURL = try fileStorageManager.migrateDatabaseToSharedStorageIfNeeded(from: originalURL, to: sharedDatabaseURL)

        XCTAssertEqual(resultURL, sharedDatabaseURL, "The shared database URL should be returned since it already exists.")
        XCTAssertTrue(mockFileManager.files.contains(sharedDatabaseURL), "The shared database should still exist.")
        XCTAssertTrue(mockFileManager.files.contains(originalURL), "The original file should not be deleted if the shared database already exists.")
    }

    func testWhenMigrateDatabaseToSharedStorageIfNeeded_ThenRestoresOriginalIfCopyFails() throws {
        let originalURL = URL(fileURLWithPath: "/path/to/Vault.db")
        let sharedDatabaseURL = URL(fileURLWithPath: "/shared/path/Vault.db")

        mockFileManager.files.insert(originalURL)
        // Simulate copy failure
        mockFileManager.shouldFailOnCopy = true

        var returnedURL: URL?
        do {
            returnedURL = try fileStorageManager.migrateDatabaseToSharedStorageIfNeeded(from: originalURL, to: sharedDatabaseURL)
            XCTFail("Expected failure when copying the file.")
        } catch {
            // Expected failure
        }

        XCTAssertNil(returnedURL, "The migration should fail and no URL should be returned.")
        XCTAssertTrue(mockFileManager.files.contains(originalURL), "The original file should still exist after a failed migration.")
    }
}

final class MockFileManager: FileManager {
    var files: Set<URL> = []
    var createdDirectories: Set<URL> = []
    var copiedFiles: [(from: URL, to: URL)] = []
    var movedFiles: [(from: URL, to: URL)] = []
    var removedFiles: [URL] = []
    var shouldFailOnCopy = false

    override func fileExists(atPath path: String) -> Bool {
        return files.contains(URL(fileURLWithPath: path))
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if shouldFailOnCopy {
            throw NSError(domain: "MockFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated copy failure"])
        }
        if !files.contains(srcURL) {
            throw NSError(domain: "MockFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        files.insert(dstURL)
        copiedFiles.append((from: srcURL, to: dstURL))
    }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        createdDirectories.insert(url)
    }

    override func removeItem(at URL: URL) throws {
        if !files.contains(URL) {
            throw NSError(domain: "MockFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        files.remove(URL)
        removedFiles.append(URL)
    }
}
