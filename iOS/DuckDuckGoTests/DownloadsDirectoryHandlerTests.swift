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

    func testDownloadsDirectoryFilesProperty() {
        XCTAssertTrue(handler.downloadsDirectoryFiles.isEmpty)

        let fileURL = handler.downloadsDirectory.appendingPathComponent("testFile.txt")
        try? FileManager.default.createDirectory(at: handler.downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        XCTAssertEqual(handler.downloadsDirectoryFiles, [fileURL])

        let subdirectoryURL = handler.downloadsDirectory.appendingPathComponent("Subdirectory")
        try? FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
        XCTAssertEqual(handler.downloadsDirectoryFiles, [fileURL])
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
}
