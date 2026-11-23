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
    var testDirectory: URL!
    var restoredFileURLs: [URL] = []

    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true, attributes: nil)
        spyDownloadManager = SpyDownloadManager()
        spyDownloadManager.downloadsDirectory = testDirectory
    }

    override func tearDown() {
        sut = nil
        spyDownloadManager = nil
        try? FileManager.default.removeItem(at: testDirectory)
        restoredFileURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        restoredFileURLs = []
        super.tearDown()
    }

    func testWhenInitializedThenModelContainsNonTemporaryOngoingDownloadsAndDirectoryFiles() {
        let ongoing = makeDownload(filename: "ongoing.zip")
        let temporary = makeDownload(filename: "temporary.pkpass", temporary: true)
        spyDownloadManager.downloadList = [ongoing, temporary]
        let file = makeFile(named: "complete.pdf")

        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)

        XCTAssertEqual(sut.model.ongoingDownloads.map(\.filename), ["ongoing.zip"])
        XCTAssertEqual(sut.model.ongoingDownloads.map(\.type), [.ongoing])
        XCTAssertEqual(sut.model.completeDownloads.map(\.filename), [file.lastPathComponent])
        XCTAssertEqual(sut.model.completeDownloads.map(\.type), [.complete])
    }

    func testWhenNoDownloadsThenModelIsEmpty() {
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)

        XCTAssertTrue(sut.model.ongoingDownloads.isEmpty)
        XCTAssertTrue(sut.model.completeDownloads.isEmpty)
    }

    func testWhenDownloadsDirectoryChangesThenModelIsUpdated() {
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        XCTAssertTrue(sut.model.completeDownloads.isEmpty)

        let file = makeFile(named: "new.pdf")
        NotificationCenter.default.post(name: .downloadsDirectoryChanged, object: nil)

        XCTAssertEqual(sut.model.completeDownloads.map(\.filename), [file.lastPathComponent])
    }

    func testWhenDownloadStartsThenOngoingDownloadIsAddedToModel() {
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        XCTAssertTrue(sut.model.ongoingDownloads.isEmpty)

        spyDownloadManager.downloadList = [makeDownload(filename: "started.zip")]
        NotificationCenter.default.post(name: .downloadStarted, object: nil)

        XCTAssertEqual(sut.model.ongoingDownloads.map(\.filename), ["started.zip"])
    }

    func testWhenCancelDownloadWithIdentifierThenMatchingDownloadIsCancelled() {
        let first = makeDownload(filename: "first.zip")
        let second = makeDownload(filename: "second.zip")
        spyDownloadManager.downloadList = [first, second]
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)

        sut.cancelDownloadWithIdentifier("second.zip")

        XCTAssertEqual(spyDownloadManager.cancelledDownloads, [second])
    }

    func testWhenCancelDownloadWithUnknownIdentifierThenNothingIsCancelled() {
        spyDownloadManager.downloadList = [makeDownload(filename: "first.zip")]
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)

        sut.cancelDownloadWithIdentifier("unknown.zip")

        XCTAssertTrue(spyDownloadManager.cancelledDownloads.isEmpty)
    }

    func testWhenDeleteDownloadWithIdentifierThenFileIsRemovedAndModelIsUpdated() {
        let kept = makeFile(named: "kept.pdf")
        let deleted = makeFile(named: "deleted.pdf")
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        var result: DeleteResult?

        sut.deleteDownloadWithIdentifier(deleted.lastPathComponent) { result = $0 }

        XCTAssertTrue(isSuccess(result))
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
        XCTAssertEqual(sut.model.completeDownloads.map(\.filename), [kept.lastPathComponent])
    }

    func testWhenDeleteDownloadWithUnknownIdentifierThenCompletionIsNotCalled() {
        let file = makeFile(named: "file.pdf")
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        var completionCalled = false

        sut.deleteDownloadWithIdentifier("unknown.pdf") { _ in completionCalled = true }

        XCTAssertFalse(completionCalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testWhenDeleteAllDownloadsThenAllFilesAreRemovedAndModelIsEmpty() {
        let first = makeFile(named: "first.pdf")
        let second = makeFile(named: "second.pdf")
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        var result: DeleteResult?

        sut.deleteAllDownloads { result = $0 }

        XCTAssertTrue(isSuccess(result))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(sut.model.completeDownloads.isEmpty)
    }

    func testWhenDeleteAllDownloadsThenOngoingDownloadsAreKept() {
        spyDownloadManager.downloadList = [makeDownload(filename: "ongoing.zip")]
        _ = makeFile(named: "complete.pdf")
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)

        sut.deleteAllDownloads { _ in }

        XCTAssertEqual(sut.model.ongoingDownloads.map(\.filename), ["ongoing.zip"])
        XCTAssertTrue(spyDownloadManager.cancelledDownloads.isEmpty)
    }

    func testWhenDeleteAllDownloadsWithNoFilesThenFailsWithFileNotFound() {
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        var result: DeleteResult?

        sut.deleteAllDownloads { result = $0 }

        guard case .failure(let error) = result else {
            return XCTFail("Expected a failure, got \(String(describing: result))")
        }
        XCTAssertEqual(error, .fileNotFound)
    }

    func testWhenUndoIsCalledAfterDeleteThenFileIsMovedToDownloadsDirectory() throws {
        let deleted = makeFile(named: "\(UUID().uuidString).pdf")
        let restoredURL = try prepareRestoreLocation(for: deleted)
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        var result: DeleteResult?
        sut.deleteDownloadWithIdentifier(deleted.lastPathComponent) { result = $0 }
        guard case .success(let undo) = result else {
            return XCTFail("Expected a success, got \(String(describing: result))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.path))

        undo()

        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredURL.path))
    }

    func testWhenUndoIsCalledAfterDeleteAllThenAllFilesAreMovedToDownloadsDirectory() throws {
        let first = makeFile(named: "\(UUID().uuidString).pdf")
        let second = makeFile(named: "\(UUID().uuidString).pdf")
        let restoredURLs = try [first, second].map { try prepareRestoreLocation(for: $0) }
        sut = DownloadsListDataSource(downloadManager: spyDownloadManager)
        var result: DeleteResult?
        sut.deleteAllDownloads { result = $0 }
        guard case .success(let undo) = result else {
            return XCTFail("Expected a success, got \(String(describing: result))")
        }

        undo()

        for restoredURL in restoredURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: restoredURL.path))
        }
    }

    private func makeDownload(filename: String, temporary: Bool = false) -> Download {
        Download(url: URL(string: "https://duck.com/\(filename)")!,
                 filename: filename,
                 mimeType: .octetStream,
                 temporary: temporary,
                 downloadSession: MockDownloadSession())
    }

    @discardableResult
    private func makeFile(named name: String) -> URL {
        let url = testDirectory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("content".utf8), attributes: nil)
        return url
    }

    private func prepareRestoreLocation(for file: URL) throws -> URL {
        let downloadsDirectory = AppDependencyProvider.shared.downloadManager.downloadsDirectory
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)
        let restoredURL = downloadsDirectory.appendingPathComponent(file.lastPathComponent)
        restoredFileURLs.append(restoredURL)
        return restoredURL
    }

    private func isSuccess(_ result: DeleteResult?) -> Bool {
        if case .success = result {
            return true
        }
        return false
    }
}
