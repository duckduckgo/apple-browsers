//
//  BookmarkDomainsTests.swift
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

import BookmarksTestsUtils
import CoreData
import Foundation
import Persistence
import XCTest
@testable import Bookmarks

final class BookmarkDomainsTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var location: URL!

    override func setUp() {
        super.setUp()

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testThatAllFavoritesDictionariesKeysAreDisjoint() throws {
        let bookmarkDomains = populateDatabaseAndMakeBookmarkDomains {
            Bookmark(id: "1", url: "https://1.com")
            Bookmark(id: "2", url: "https://2.com")
            Folder {
                Bookmark(id: "3", url: "https://3.com")
                Bookmark(id: "4", url: "https://4.com")
                Bookmark(id: "5", url: "https://5.com", favoritedOn: [.mobile, .unified])
                Bookmark(id: "6", url: "https://6.com")
            }
            Bookmark(id: "7", url: "https://7.com")
        }

        XCTAssertEqual(bookmarkDomains.favoritesDomainsToUUIDs, ["5.com": ["5"]])
        XCTAssertEqual(bookmarkDomains.topLevelBookmarksDomainsToUUIDs, [
            "1.com": ["1"],
            "2.com": ["2"],
            "7.com": ["7"]
        ])
        XCTAssertEqual(bookmarkDomains.otherBookmarksDomainsToUUIDs, [
            "3.com": ["3"],
            "4.com": ["4"],
            "6.com": ["6"]
        ])
        XCTAssertEqual(Set(bookmarkDomains.allDomains), ["1.com", "2.com", "3.com", "4.com", "5.com", "6.com", "7.com"])
        XCTAssertEqual(Set(bookmarkDomains.allUUIDs), ["1", "2", "3", "4", "5", "6", "7"])
    }

    func testThatFavoritesDomainMayContainTopLevelOrOtherBookmarksUUIDs() throws {
        let bookmarkDomains = populateDatabaseAndMakeBookmarkDomains {
            Bookmark(id: "1", url: "https://1.com/1")
            Bookmark(id: "2", url: "https://1.com/2")
            Folder {
                Bookmark(id: "3", url: "https://1.com/3")
                Bookmark(id: "4", url: "https://1.com/4")
                Bookmark(id: "5", url: "https://1.com/5", favoritedOn: [.mobile, .unified])
                Bookmark(id: "6", url: "https://2.com/6")
            }
            Bookmark(id: "7", url: "https://2.com/7")
        }
        XCTAssertEqual(bookmarkDomains.favoritesDomainsToUUIDs, ["1.com": ["1", "2", "3", "4", "5"]])
        XCTAssertEqual(bookmarkDomains.topLevelBookmarksDomainsToUUIDs, ["2.com": ["6", "7"]])
        XCTAssertEqual(bookmarkDomains.otherBookmarksDomainsToUUIDs, [:])
        XCTAssertEqual(Set(bookmarkDomains.allDomains), ["1.com", "2.com"])
        XCTAssertEqual(Set(bookmarkDomains.allUUIDs), ["1", "2", "3", "4", "5", "6", "7"])
    }

    func testThatTopLevelDomainMayContainOtherBookmarksUUIDs() throws {
        let bookmarkDomains = populateDatabaseAndMakeBookmarkDomains {
            Bookmark(id: "1", url: "https://1.com/1")
            Bookmark(id: "2", url: "https://1.com/2")
            Folder {
                Bookmark(id: "3", url: "https://1.com/3")
                Bookmark(id: "4", url: "https://1.com/4")
                Bookmark(id: "5", url: "https://1.com/5")
                Bookmark(id: "6", url: "https://2.com/6")
            }
            Bookmark(id: "7", url: "https://2.com/7")
        }
        XCTAssertEqual(bookmarkDomains.favoritesDomainsToUUIDs, [:])
        XCTAssertEqual(bookmarkDomains.topLevelBookmarksDomainsToUUIDs, [
            "1.com": ["1", "2", "3", "4", "5"],
            "2.com": ["6", "7"]
        ])
        XCTAssertEqual(bookmarkDomains.otherBookmarksDomainsToUUIDs, [:])
        XCTAssertEqual(Set(bookmarkDomains.allDomains), ["1.com", "2.com"])
        XCTAssertEqual(Set(bookmarkDomains.allUUIDs), ["1", "2", "3", "4", "5", "6", "7"])
    }

    func testThatAllDomainsHasUniqueEntries() throws {
        let bookmarkDomains = populateDatabaseAndMakeBookmarkDomains {
            Bookmark(id: "1", url: "https://1.com/1")
            Bookmark(id: "2", url: "https://2.com/1")
            Bookmark(id: "3", url: "https://3.com/1")
            Folder {
                Bookmark(id: "4", url: "https://1.com/4")
                Bookmark(id: "5", url: "https://2.com/5")
                Bookmark(id: "6", url: "https://3.com/6")
                Bookmark(id: "7", url: "https://1.com/4", favoritedOn: [.mobile, .unified])
                Bookmark(id: "8", url: "https://2.com/5", favoritedOn: [.mobile, .unified])
                Bookmark(id: "9", url: "https://3.com/6", favoritedOn: [.mobile, .unified])
            }
        }
        XCTAssertEqual(bookmarkDomains.favoritesDomainsToUUIDs, [
            "1.com": ["1", "4", "7"],
            "2.com": ["2", "5", "8"],
            "3.com": ["3", "6", "9"]
        ])
        XCTAssertEqual(bookmarkDomains.topLevelBookmarksDomainsToUUIDs, [:])
        XCTAssertEqual(bookmarkDomains.otherBookmarksDomainsToUUIDs, [:])
        XCTAssertEqual(Set(bookmarkDomains.allDomains), ["1.com", "2.com", "3.com"])
        XCTAssertEqual(Set(bookmarkDomains.allUUIDs), ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
    }

    // MARK: - Private

    private func populateDatabaseAndMakeBookmarkDomains(@BookmarkTreeBuilder with builder: () -> [BookmarkTreeNode]) -> BookmarkDomains {
        let bookmarkTree = BookmarkTree(builder: builder)
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var bookmarkDomains: BookmarkDomains!
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
            bookmarkDomains = BookmarkDomains.make(withAllBookmarksIn: context)
        }
        return bookmarkDomains
    }
}

private extension BookmarkDomains {

    static func make(withAllBookmarksIn context: NSManagedObjectContext) -> BookmarkDomains {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == NO AND %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.propertiesToFetch = [#keyPath(BookmarkEntity.url)]
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.favoriteFolders), #keyPath(BookmarkEntity.parent)]

        var bookmarkDomains: BookmarkDomains!
        context.performAndWait {
            let bookmarks = (try? context.fetch(request)) ?? []
            bookmarkDomains = .init(bookmarks: bookmarks)
        }
        return bookmarkDomains
    }
}
