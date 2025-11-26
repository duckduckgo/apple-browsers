//
//  DownloadsListDataSourceTests.swift
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

class DownloadsListDataSourceTests: XCTestCase {
    var sut: DownloadsListDataSource!
    var spyDownloadManager: SpyDownloadManager!
    
    override func setUp() {
        super.setUp()
        spyDownloadManager = SpyDownloadManager()
    }
    
    override func tearDown() {
        sut = nil
        spyDownloadManager = nil
        super.tearDown()
    }
    
    func testDeleteDownloadsDirectoryIfNeededWhenAllEmpty() {
        // Given
        spyDownloadManager.downloadList = []
        spyDownloadManager.downloadsDirectoryFiles = []
        
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        
        XCTAssertEqual(spyDownloadManager.deleteDownloadsDirectoryIfEmptyCallCount, 1, "Called on init")
        
        // When - trigger updateModel by posting a notification
        NotificationCenter.default.post(name: .downloadsDirectoryChanged, object: nil)
        waitForProcessing()
        
        // Then
        XCTAssertEqual(spyDownloadManager.deleteDownloadsDirectoryIfEmptyCallCount, 2, "delete downloads should be called when all downloads cleared")
    }
    
    func testDeleteDownloadsDirectoryIfNeededWhenTemporaryDirectoriesExist() {
        // Given
        let downloadsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
        let fileToDelete = downloadsDirectory.appendingPathComponent("file.txt")
        FileManager.default.createFile(atPath: fileToDelete.path, contents: Data("content".utf8), attributes: nil)
        
        spyDownloadManager.downloadList = []
        spyDownloadManager.downloadsDirectoryFiles = [fileToDelete]
        
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        
        // Delete the file to create temporary directory
        let deleteExpectation = XCTestExpectation(description: "Delete completion")
        sut.deleteDownloadWithIdentifier("file.txt") { _ in
            deleteExpectation.fulfill()
        }
        
        wait(for: [deleteExpectation], timeout: 1.0)
        
        // Update model to reflect deletion (simulating file system state)
        spyDownloadManager.downloadsDirectoryFiles = []
        
        // When - trigger update
        NotificationCenter.default.post(name: .downloadsDirectoryChanged, object: nil)
        waitForProcessing()
        
        // Then
        XCTAssertEqual(spyDownloadManager.deleteDownloadsDirectoryIfEmptyCallCount, 0, "delete downloads should not be called while temporary directories exist")
        
        // Cleanup
        try? FileManager.default.removeItem(at: downloadsDirectory)
    }
    
    func testDeleteDownloadsDirectoryIfNeededWhenOngoingDownloadsExist() {
        // Given
        let mockDownload = Download(url: URL(string: "https://example.com/file.zip")!,
                                    filename: "file.zip",
                                    mimeType: .unknown,
                                    temporary: false,
                                    downloadSession: MockDownloadSession(),
                                    delegate: nil)
        spyDownloadManager.downloadList = [mockDownload]
        spyDownloadManager.downloadsDirectoryFiles = []
        
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        
        // When - trigger update
        NotificationCenter.default.post(name: .downloadStarted, object: nil)
        waitForProcessing()
        
        // Then
        XCTAssertEqual(spyDownloadManager.deleteDownloadsDirectoryIfEmptyCallCount, 0, "delete downloads should not be called when ongoing downloads exist")
    }
    
    func testDeleteDownloadsDirectoryIfNeededWhenCompletedDownloadsExist() {
        // Given
        let completedFileURL = URL(fileURLWithPath: "/tmp/completed.txt")
        spyDownloadManager.downloadList = []
        spyDownloadManager.downloadsDirectoryFiles = [completedFileURL]
        
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        
        // When - trigger update
        NotificationCenter.default.post(name: .downloadsDirectoryChanged, object: nil)
        waitForProcessing()
        
        // Then
        XCTAssertEqual(spyDownloadManager.deleteDownloadsDirectoryIfEmptyCallCount, 0, "delete downloads should not be called when completed downloads exist")
    }
    
    private func waitForProcessing() {
        let processExpectation = XCTestExpectation(description: "Processing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            processExpectation.fulfill()
        }
        wait(for: [processExpectation], timeout: 1.0)
    }
}
