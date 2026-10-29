//
//  ChromiumBookmarksReaderTests.swift
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

class ChromiumBookmarksReaderTests: XCTestCase {

    func testImportingBookmarks() {
        let bookmarksReader = ChromiumBookmarksReader(chromiumDataDirectoryURL: resourceURL())
        let bookmarks = bookmarksReader.readBookmarks()

        guard case let .success(bookmarks) = bookmarks else {
            XCTFail("Failed to decode bookmarks")
            return
        }

        XCTAssertEqual(bookmarks.topLevelFolders.bookmarkBar?.type, .folder)
        XCTAssertEqual(bookmarks.topLevelFolders.otherBookmarks?.type, .folder)
    }

    func testWhenOnlyAccountBookmarksFileExists_ThenItsBookmarksAreRead() throws {
        let profileURL = try makeProfile(files: ["AccountBookmarks": bookmarksJSON(barURLs: ["https://account.example"])])
        let bookmarksReader = ChromiumBookmarksReader(chromiumDataDirectoryURL: profileURL)

        let bookmarks = try bookmarksReader.readBookmarks().get()

        XCTAssertEqual(barURLs(of: bookmarks), ["https://account.example"])
    }

    func testWhenBothBookmarksFilesExist_ThenTheirBookmarksAreCombined() throws {
        let profileURL = try makeProfile(files: [
            "Bookmarks": bookmarksJSON(barURLs: ["https://local.example"]),
            "AccountBookmarks": bookmarksJSON(barURLs: ["https://account.example"])
        ])
        let bookmarksReader = ChromiumBookmarksReader(chromiumDataDirectoryURL: profileURL)

        let bookmarks = try bookmarksReader.readBookmarks().get()

        XCTAssertEqual(barURLs(of: bookmarks), ["https://local.example", "https://account.example"])
        XCTAssertEqual(bookmarks.topLevelFolders.bookmarkBar?.type, .folder)
    }

    private func makeProfile(files: [String: String]) throws -> URL {
        let profileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: profileURL) }
        for (name, contents) in files {
            try contents.write(to: profileURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return profileURL
    }

    private func bookmarksJSON(barURLs: [String]) -> String {
        let children = barURLs.map { #"{ "name": "\#($0)", "type": "url", "url": "\#($0)" }"# }
        return """
        { "roots": {
            "bookmark_bar": { "name": "Bookmarks bar", "type": "folder", "children": [\(children.joined(separator: ","))] },
            "other": { "name": "Other bookmarks", "type": "folder", "children": [] }
        } }
        """
    }

    private func barURLs(of bookmarks: ImportedBookmarks) -> [String?] {
        bookmarks.topLevelFolders.bookmarkBar?.children?.map(\.urlString) ?? []
    }

    private func resourceURL() -> URL {
        let bundle = Bundle(for: ChromiumBookmarksReaderTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestChromeData")
    }

}
