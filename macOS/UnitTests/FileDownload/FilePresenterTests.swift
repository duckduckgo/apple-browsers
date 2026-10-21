//
//  FilePresenterTests.swift
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

import AppKitExtensions
import Foundation
import FoundationExtensions
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FilePresenterTests: XCTestCase {

    let fm = FileManager()
    let testData = "test data".utf8data

    override var allowedNonNilVariables: Set<String> {
        ["fm"]
    }

    private func makeNonSandboxFile() throws -> URL {
        let fileName = UUID().uuidString + ".txt"
        let fileURL = fm.temporaryDirectory.appendingPathComponent(fileName)
        try testData.write(to: fileURL)

        return fileURL
    }

    // MARK: - Test non-sandboxed file access

    func testWhenSandboxFilePresenterIsOpen_itCanReadFile_accessIsNotStoppedWhenClosed_noSandbox() async throws {
        // 1. make non-sandbox file; create bookmark
        let nonSandboxUrl = try makeNonSandboxFile()
        guard let bookmarkData = try BookmarkFilePresenter(url: nonSandboxUrl).fileBookmarkData else { XCTFail("No bookmark"); return }

        // 2. open the bookmark with BookmarkFilePresenter
        var filePresenter: BookmarkFilePresenter! = try BookmarkFilePresenter(fileBookmarkData: bookmarkData)

        // 3. validate
        var publishedUrl: URL?
        _=filePresenter.urlPublisher.sink { publishedUrl = $0 }
        var publishedBookmarkData: Data?
        _=filePresenter.fileBookmarkDataPublisher.sink { publishedBookmarkData = $0 }
        XCTAssertEqual(filePresenter.url?.resolvingSymlinksInPath(), nonSandboxUrl.resolvingSymlinksInPath())
        XCTAssertEqual(publishedUrl?.resolvingSymlinksInPath(), nonSandboxUrl.resolvingSymlinksInPath())
        XCTAssertEqual(filePresenter.fileBookmarkData, bookmarkData)
        XCTAssertEqual(publishedBookmarkData, bookmarkData)

        // 4. close file presenter, access should not stop
        filePresenter = nil
        XCTAssertEqual(try Data(contentsOf: nonSandboxUrl), testData)
    }

    func testWhenFileIsRenamed_urlIsUpdated_noSandbox() async throws {
        // 1. make non-sandbox file
        let nonSandboxUrl = try makeNonSandboxFile()
        let filePresenter = try BookmarkFilePresenter(url: nonSandboxUrl)

        // 4. rename the file
        let newUrl = nonSandboxUrl.deletingPathExtension().appendingPathExtension("1.txt")
        let e1 = expectation(description: "file presenter: file renamed")
        let c1 = filePresenter.urlPublisher.dropFirst().sink { url in
            XCTAssertEqual(newUrl, url)
            e1.fulfill()
        }
        let e2 = expectation(description: "file presenter: bookmark updated")
        var newFileBookmarkData: Data?
        let c2 = filePresenter.fileBookmarkDataPublisher.dropFirst().sink { bookmark in
            newFileBookmarkData = bookmark
            e2.fulfill()
        }

        try NSFileCoordinator().coordinateMove(from: nonSandboxUrl, to: newUrl) { from, to in
            try FileManager.default.moveItem(at: from, to: to)
        }
        await fulfillment(of: [e1, e2], timeout: 5)
        withExtendedLifetime((c1, c2)) {}

        let bookmarkData = try newUrl.bookmarkData(options: .withSecurityScope)

        // url&bookmark should update
        XCTAssertEqual(filePresenter.url, newUrl)
        XCTAssertEqual(filePresenter.fileBookmarkData, bookmarkData)
        XCTAssertEqual(newFileBookmarkData, bookmarkData)
    }

    func testWhenFileIsRemoved_removalIsDetected_noSandbox() async throws {
        // 1. make non-sandbox file
        let nonSandboxUrl = try makeNonSandboxFile()
        let filePresenter = try BookmarkFilePresenter(url: nonSandboxUrl)

        // 2. remove the file
        let e1 = expectation(description: "file presenter: file removed")
        let e2 = expectation(description: "file presenter: bookmark updated")
        let c1 = filePresenter.urlPublisher.dropFirst().sink { url in
            XCTAssertNil(url)
            e1.fulfill()
        }
        let c2 = filePresenter.fileBookmarkDataPublisher.dropFirst().sink { bookmark in
            XCTAssertNil(bookmark)
            e2.fulfill()
        }

        try NSFileCoordinator().coordinateWrite(at: nonSandboxUrl, with: .forDeleting) { url in
            try FileManager.default.removeItem(at: url)
        }
        await fulfillment(of: [e1, e2], timeout: 5)
        withExtendedLifetime((c1, c2)) {}
    }

    func testWhen2FilesAreCrossRenamedAnd1stFileClosed_accessTo2ndIsPreserved_noSandbox() async throws {
        // 1. make 2 non-sandbox files
        let nonSandboxUrl1 = try makeNonSandboxFile()
        let bookmarkData1 = try nonSandboxUrl1.bookmarkData(options: .withSecurityScope)
        let nonSandboxUrl2 = try makeNonSandboxFile()
        let bookmarkData2 = try nonSandboxUrl2.bookmarkData(options: .withSecurityScope)
        let filePresenter1 = try BookmarkFilePresenter(fileBookmarkData: bookmarkData1)
        let filePresenter2 = try BookmarkFilePresenter(fileBookmarkData: bookmarkData2)

        // 2. cross-rename the files
        let tempUrl = nonSandboxUrl1.appendingPathExtension("tmp")
        var newBookmarkData1: Data?
        var newBookmarkData2: Data?
        for (from, to, presenter) in [(nonSandboxUrl1, tempUrl, filePresenter1), (nonSandboxUrl2, nonSandboxUrl1, filePresenter2), (tempUrl, nonSandboxUrl2, filePresenter1)] {
            let e1 = expectation(description: "file presenter: file renamed")
            let c1 = presenter.urlPublisher.dropFirst().sink { [unowned presenter] url in
                XCTAssertEqual(url, presenter.url)
                XCTAssertEqual(to, url)
                e1.fulfill()
            }
            let e2 = expectation(description: "file presenter: bookmark updated")
            let c2 = presenter.fileBookmarkDataPublisher.dropFirst().sink { [unowned presenter] bookmarkData in
                XCTAssertEqual(bookmarkData, presenter.fileBookmarkData)
                if presenter === filePresenter1 {
                    newBookmarkData1 = bookmarkData
                } else {
                    newBookmarkData2 = bookmarkData
                }
                e2.fulfill()
            }
            let c3 = ((presenter === filePresenter1) ? filePresenter2 : filePresenter1).urlPublisher.dropFirst().sink { _ in
                XCTFail("Unexpected url published from another file presenter")
            }
            try NSFileCoordinator().coordinateMove(from: from, to: to) { from, to in
                try FileManager.default.moveItem(at: from, to: to)
            }
            await fulfillment(of: [e1, e2], timeout: 5)
            withExtendedLifetime((c1, c2, c3)) {}
        }

        XCTAssertEqual(filePresenter1.url, nonSandboxUrl2)
        XCTAssertEqual(filePresenter2.url, nonSandboxUrl1)
        var isStale = false
        XCTAssertEqual(newBookmarkData1, filePresenter1.fileBookmarkData)
        XCTAssertEqual(try URL(resolvingBookmarkData: filePresenter1.fileBookmarkData ?? Data(), bookmarkDataIsStale: &isStale).resolvingSymlinksInPath(),
                       nonSandboxUrl2.resolvingSymlinksInPath())
        // XCTAssertFalse(isStale) - why it‘s false?
        XCTAssertEqual(newBookmarkData2, filePresenter2.fileBookmarkData)
        XCTAssertEqual(try URL(resolvingBookmarkData: filePresenter2.fileBookmarkData ?? Data(), bookmarkDataIsStale: &isStale).resolvingSymlinksInPath(),
                       nonSandboxUrl1.resolvingSymlinksInPath())
        // XCTAssertFalse(isStale) - why it‘s false?
    }

}
