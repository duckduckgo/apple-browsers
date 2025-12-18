//
//  DownloadsDirectoryHandlerTests.swift
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
@testable import DuckDuckGo

class DownloadsDirectoryHandlerTests: XCTestCase {
    var handler: DownloadsDirectoryHandler!

    override func setUp() {
        super.setUp()
        handler = DownloadsDirectoryHandler()
        try? FileManager.default.removeItem(at: handler.downloadsDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: handler.downloadsDirectory)
        handler = nil
        super.tearDown()
    }

    func testDownloadsDirectoryProperty() {
        let expectedPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Downloads", isDirectory: true)
        XCTAssertEqual(handler.downloadsDirectory.standardizedFileURL, expectedPath.standardizedFileURL)
    }

    func testDownloadsDirectoryFilesProperty() throws {
        XCTAssert(try handler.downloadsDirectoryFiles.isEmpty)

        let fileURL = handler.downloadsDirectory.appendingPathComponent("testFile.txt")
        try? FileManager.default.createDirectory(at: handler.downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        XCTAssertEqual(try handler.downloadsDirectoryFiles, [fileURL])

        let subdirectoryURL = handler.downloadsDirectory.appendingPathComponent("Subdirectory")
        try? FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
        XCTAssertEqual(try handler.downloadsDirectoryFiles, [fileURL])
    }

    func testCreateDownloadsDirectoryIfNeeded() {
        handler.createDownloadsDirectoryIfNeeded()
        XCTAssertTrue(handler.downloadsDirectoryExists())

        let initialModificationDate = try? FileManager.default.attributesOfItem(atPath: handler.downloadsDirectory.path)[.modificationDate] as? Date
        handler.createDownloadsDirectoryIfNeeded()
        let newModificationDate = try? FileManager.default.attributesOfItem(atPath: handler.downloadsDirectory.path)[.modificationDate] as? Date
        XCTAssertEqual(initialModificationDate, newModificationDate)
    }

    func testDownloadsDirectoryExists() {
        XCTAssertFalse(handler.downloadsDirectoryExists())

        handler.createDownloadsDirectory()
        XCTAssertTrue(handler.downloadsDirectoryExists())
    }

    func testDeleteDownloadsDirectoryIfEmptyWhenDirectoryDoesNotExist() {
        // Given
        XCTAssertFalse(handler.downloadsDirectoryExists())
        
        // When
        handler.deleteDownloadsDirectoryIfEmpty()
        
        // Then - should not crash or throw
        XCTAssertFalse(handler.downloadsDirectoryExists())
    }

    func testDeleteDownloadsDirectoryIfEmptyWhenDirectoryIsEmpty() throws {
        // Given
        handler.createDownloadsDirectory()
        XCTAssertTrue(handler.downloadsDirectoryExists())
        XCTAssertTrue(try handler.downloadsDirectoryFiles.isEmpty)
        
        // When
        handler.deleteDownloadsDirectoryIfEmpty()
        
        // Then
        XCTAssertFalse(handler.downloadsDirectoryExists(), "Empty directory should be deleted")
    }

    func testDeleteDownloadsDirectoryIfEmptyWhenDirectoryHasFiles() throws {
        // Given
        handler.createDownloadsDirectory()
        let fileURL = handler.downloadsDirectory.appendingPathComponent("testFile.txt")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        XCTAssertFalse(try handler.downloadsDirectoryFiles.isEmpty)
        
        // When
        handler.deleteDownloadsDirectoryIfEmpty()
        
        // Then
        XCTAssertTrue(handler.downloadsDirectoryExists(), "Directory with files should not be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "File should still exist")
    }

    func testDeleteDownloadsDirectoryIfEmptyWhenDirectoryHasOnlySubdirectories() throws {
        // Given
        handler.createDownloadsDirectory()
        let subdirectoryURL = handler.downloadsDirectory.appendingPathComponent("Subdirectory")
        try? FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
        
        // downloadsDirectoryFiles filters out directories
        XCTAssertTrue(try handler.downloadsDirectoryFiles.isEmpty, "Should be empty (no files)")
        
        // When
        handler.deleteDownloadsDirectoryIfEmpty()
        
        // Then
        XCTAssertFalse(handler.downloadsDirectoryExists(), "Directory with only subdirectories should be deleted")
    }

    func testDeleteDownloadsDirectoryIfEmptyWhenReadingDirectoryThrowsThenDirectoryNotDeleted() throws {
        // Given
        handler.createDownloadsDirectory()
        XCTAssertTrue(handler.downloadsDirectoryExists())
        
        // Remove read permissions to force contentsOfDirectory to throw
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: handler.downloadsDirectory.path)
        
        // When
        handler.deleteDownloadsDirectoryIfEmpty()
        
        // Restore permissions so we can check existence and tearDown can clean up
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: handler.downloadsDirectory.path)
        
        // Then
        XCTAssertTrue(handler.downloadsDirectoryExists(), "Directory should not be deleted when reading throws")
    }
}
