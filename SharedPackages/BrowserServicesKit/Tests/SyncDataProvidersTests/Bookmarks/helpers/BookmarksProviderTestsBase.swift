//
//  BookmarksProviderTestsBase.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Foundation
import DDGSync
import Persistence
@testable import SyncDataProviders

internal class BookmarksProviderTestsBase: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var bookmarksDatabaseLocation: URL!
    var metadataDatabase: CoreDataDatabase!
    var metadataDatabaseLocation: URL!
    var crypter = CryptingMock()
    var provider: BookmarksProvider!

    var expectedSyncResult: BookmarksProvider.SyncResult?

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

    func setUpSyncMetadataDatabase() {
        metadataDatabaseLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            XCTFail("Failed to load model")
            return
        }
        metadataDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: metadataDatabaseLocation, model: model)
        metadataDatabase.loadStore()
    }

    override func setUpWithError() throws {
        super.setUp()

        setUpBookmarksDatabase()
        setUpSyncMetadataDatabase()

        provider = BookmarksProvider(
            database: bookmarksDatabase,
            metadataStore: LocalSyncMetadataStore(database: metadataDatabase),
            syncDidUpdateData: {},
            syncDidFinish: { _ in }
        )
    }

    override func tearDown() {
        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: bookmarksDatabaseLocation)

        try? metadataDatabase.tearDown(deleteStores: true)
        metadataDatabase = nil
        try? FileManager.default.removeItem(at: metadataDatabaseLocation)
    }
}
