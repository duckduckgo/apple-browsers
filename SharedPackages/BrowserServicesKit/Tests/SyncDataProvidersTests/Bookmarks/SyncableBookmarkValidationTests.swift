//
//  SyncableBookmarkValidationTests.swift
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
import Bookmarks
import Common
import DDGSync
import Persistence
@testable import BrowserServicesKit
@testable import SyncDataProviders

final class SyncableBookmarkValidationTests: XCTestCase {

    var bookmark: BookmarkEntity!
    var folder: BookmarkEntity!

    var bookmarksDatabase: CoreDataDatabase!
    var bookmarksDatabaseLocation: URL!
    var context: NSManagedObjectContext!

    override func setUp() {
        setUpBookmarksDatabase()

        context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        bookmark = BookmarkEntity(context: context)
        bookmark.isFolder = false
        bookmark.title = "title"
        bookmark.url = "https://url.com"

        folder = BookmarkEntity(context: context)
        folder.isFolder = true
        folder.title = "title"
    }

    func setUpBookmarksDatabase() {
        bookmarksDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: bookmarksDatabaseLocation, model: model)
        bookmarksDatabase.loadStore()
    }

    func testWhenBookmarkFieldsPassLengthValidationThenSyncableIsInitializedWithoutThrowingErrors() throws {
        XCTAssertNoThrow(try Syncable(bookmark: bookmark, encryptedUsing: { $0 }))
    }

    func testWhenBookmarkTitleIsTooLongThenSyncableInitializerThrowsError() throws {
        bookmark.title = String(repeating: "x", count: 10000)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenBookmarkURLIsTooLongThenSyncableInitializerThrowsError() throws {
        bookmark.url = String(repeating: "x", count: 10000)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenFolderTitleIsTooLongThenItIsTruncated() throws {
        folder.title = String(repeating: "x", count: 10000)
        do {
            let syncable = try Syncable(bookmark: folder, encryptedUsing: { $0 })
            let syncableFolder = SyncableBookmarkAdapter(syncable: syncable)
            XCTAssertTrue(syncableFolder.encryptedTitle?.length() == Syncable.BookmarkValidationConstraints.maxFolderTitleLength)
        } catch {
            XCTFail("unexpected error thrown: \(error)")
        }
    }

    private func assertSyncableInitializerThrowsValidationError(file: StaticString = #file, line: UInt = #line) {
        XCTAssertThrowsError(
            try Syncable(bookmark: bookmark, encryptedUsing: { $0 }),
            file: file,
            line: line
        ) { error in
            guard case Syncable.SyncableBookmarkError.validationFailed = error else {
                XCTFail("unexpected error thrown: \(error)", file: file, line: line)
                return
            }
        }
    }
}
