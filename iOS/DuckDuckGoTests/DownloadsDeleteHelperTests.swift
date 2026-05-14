//
//  DownloadsDeleteHelperTests.swift
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
import Combine
@testable import DuckDuckGo

class DownloadsDeleteHelperTests: XCTestCase {
    var sut: DownloadsDeleteHelper!
    var testDirectory: URL!
    var downloadsDirectory: URL!
    
    override func setUp() {
        super.setUp()
        sut = DownloadsDeleteHelper(undoTimeoutInterval: 0.5)
        
        // Create test directories
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Ensure downloads directory exists for undo operations
        downloadsDirectory = AppDependencyProvider.shared.downloadManager.downloadsDirectory
        try? FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        // Clean up temporary directories
        try? FileManager.default.removeItem(at: testDirectory)
        
        sut = nil
        super.tearDown()
    }
    
    func testTemporaryDirectoryURLsInitiallyEmpty() {
        // Given
        let helper = DownloadsDeleteHelper()
        
        // Then
        XCTAssertTrue(helper.temporaryDirectoryURLs.value.isEmpty, "temporaryDirectoryURLs should be empty initially")
    }
    
    func testTemporaryDirectoryURLsAddedAfterDelete() {
        // Given
        let testFile = testDirectory.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("test".utf8), attributes: nil)
        
        let expectation = XCTestExpectation(description: "Delete completion")
        
        // When
        sut.deleteDownloads(atPaths: [testFile.path]) { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertEqual(sut.temporaryDirectoryURLs.value.count, 1, "Should have one temporary directory")
    }
    
    func testTemporaryDirectoryURLsTracksMultipleDeletes() {
        // Given
        let testFile1 = testDirectory.appendingPathComponent("test1.txt")
        let testFile2 = testDirectory.appendingPathComponent("test2.txt")
        FileManager.default.createFile(atPath: testFile1.path, contents: Data("test1".utf8), attributes: nil)
        FileManager.default.createFile(atPath: testFile2.path, contents: Data("test2".utf8), attributes: nil)
        
        let expectation1 = XCTestExpectation(description: "First delete completion")
        let expectation2 = XCTestExpectation(description: "Second delete completion")
        
        // When
        sut.deleteDownloads(atPaths: [testFile1.path]) { _ in
            expectation1.fulfill()
        }
        
        sut.deleteDownloads(atPaths: [testFile2.path]) { _ in
            expectation2.fulfill()
        }
        
        wait(for: [expectation1, expectation2], timeout: 1.0)
        
        // Then
        XCTAssertEqual(sut.temporaryDirectoryURLs.value.count, 2, "Should track both temporary directories")
    }
    
    func testUndoHandlerRemovesDirectoryFromTracking() {
        // Given
        let testFile = testDirectory.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("test".utf8), attributes: nil)
        
        let deleteExpectation = XCTestExpectation(description: "Delete completion")
        var undoHandler: DeleteUndoHandler?
        
        sut.deleteDownloads(atPaths: [testFile.path]) { result in
            if case .success(let undo) = result {
                undoHandler = undo
            }
            deleteExpectation.fulfill()
        }
        
        wait(for: [deleteExpectation], timeout: 1.0)
        XCTAssertEqual(sut.temporaryDirectoryURLs.value.count, 1, "Should have one temporary directory before undo")
        
        // When
        undoHandler?()
        
        // Then
        XCTAssertTrue(sut.temporaryDirectoryURLs.value.isEmpty, "temporaryDirectoryURLs should be empty after undo")
    }
    
    func testTimeoutRemovesDirectoryFromTracking() {
        // Given
        var cancellables: Set<AnyCancellable> = []
        let testFile = testDirectory.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("test".utf8), attributes: nil)
        
        let deleteExpectation = XCTestExpectation(description: "Delete completion")
        let timeoutExpectation = XCTestExpectation(description: "Timeout completed")
        
        sut.deleteDownloads(atPaths: [testFile.path]) { _ in
            deleteExpectation.fulfill()
        }
        
        wait(for: [deleteExpectation], timeout: 1.0)
        XCTAssertEqual(sut.temporaryDirectoryURLs.value.count, 1, "Should have one temporary directory before timeout")
        
        // When - wait for timeout (0.5 seconds + buffer)
        sut.temporaryDirectoryURLs
            .sink { urls in
                if urls.isEmpty {
                    timeoutExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        wait(for: [timeoutExpectation], timeout: 1.0)
        
        // Then
        XCTAssertTrue(sut.temporaryDirectoryURLs.value.isEmpty, "temporaryDirectoryURLs should be empty after timeout")
    }
}
