//
//  BookmarksInitialSyncResponseHandlerTests.swift
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
import BookmarksTestsUtils
import Common
import CoreData
import DDGSync
import Persistence
@testable import SyncDataProviders

final class BookmarksInitialSyncResponseHandlerTests: BookmarksProviderTestsBase {

    func testThatBookmarksAreReorderedWithinFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.rootFolder(children: ["2", "1"])]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2", "1"]) {
            Bookmark(id: "2")
            Bookmark(id: "1")
        })
    }

    func testThatNewBookmarksCanBeAppendedAtTheEndOfTheFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
        })
    }

    func testThatNewBookmarksCanBeInsertedInTheMiddleOfAFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "3")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .bookmark(id: "2")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
        })
    }

    func testThatBookmarksAreMergedInRootFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
        })
    }

    func testThatBookmarksAreMergedInSubFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("Folder", id: "1") {
                Bookmark(id: "2")
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .folder("Folder", id: "1", children: ["4"]),
            .bookmark(id: "4")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Folder("Folder", id: "1", lastChildrenArrayReceivedFromSync: ["4"]) {
                Bookmark(id: "2")
                Bookmark(id: "3")
                Bookmark(id: "4")
            }
        })
    }

    func testThatNewFavoriteCanBeAppendedToFavorites() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .favoritesFolder(favorites: ["1", "2", "3"]),
            .mobileFavoritesFolder(favorites: ["1", "2"]),
            .desktopFavoritesFolder(favorites: ["3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.desktop, .unified])
        })
    }

    func testThatFavoritesAreMergedAndRemoteFavoritesAreAppendedAtTheEnd() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "4", favoritedOn: [.mobile, .unified])
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3"]),
            .favoritesFolder(favorites: ["3"]),
            .mobileFavoritesFolder(favorites: ["3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3"]) {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "4", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.mobile, .unified])
        })
    }

    func testWhenBookmarkIsDeduplicatedThenItIsMovedInParentCollectionAndAppendedTogetherWithRemoteBookmarks() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark("2", id: "local2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3", "remote2", "4"]),
            .bookmark("2", id: "remote2"),
            .bookmark(id: "3"),
            .bookmark(id: "4")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3", "remote2", "4"]) {
            Bookmark(id: "1")
            Bookmark(id: "3")
            Bookmark("2", id: "remote2")
            Bookmark(id: "4")
        })
    }

    func testWhenDeletedBookmarkIsReceivedThenItIsDeletedLocally() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .bookmark(id: "1", isDeleted: true)
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2"]) {
            Bookmark(id: "2")
        })
    }

    func testThatDeletesForNonExistentBookmarksAreIgnored() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2"]),
            .bookmark(id: "3", isDeleted: true),
            .bookmark(id: "4", isDeleted: true),
            .bookmark(id: "5", isDeleted: true),
            .bookmark(id: "6", isDeleted: true),
            .bookmark(id: "7", isDeleted: true)
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
        })
    }

    func testThatSinglePayloadCanDeleteCreateReorderAndDeduplicateBookmarks() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark("2", id: "local2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3", "remote2", "4"]),
            .bookmark(id: "1", isDeleted: true),
            .bookmark("2", id: "remote2"),
            .bookmark(id: "3"),
            .bookmark(id: "4")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3", "remote2", "4"]) {
            Bookmark(id: "3")
            Bookmark("2", id: "remote2")
            Bookmark(id: "4")
        })
    }

    // MARK: - Deduplication

    func testThatBookmarksWithTheSameNameAndURLAreDeduplicated() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("name", id: "1", url: "url")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .bookmark("name", id: "2", url: "url")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withLastChildrenArrayReceivedFromSync: true, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2"]) {
            Bookmark("name", id: "2", url: "url")
        })
    }

    func testThatBookmarksWithTheSameNameAndURLInsideSubfolderAreDeduplicated() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Folder(id: "2") {
                    Folder(id: "3") {
                        Bookmark("name", id: "4", url: "url")
                    }
                }
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .folder(id: "1", children: ["2"]),
            .folder(id: "2", children: ["3"]),
            .folder(id: "3", children: ["5"]),
            .bookmark("name", id: "5", url: "url")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Folder(id: "1", lastChildrenArrayReceivedFromSync: ["2"]) {
                Folder(id: "2", lastChildrenArrayReceivedFromSync: ["3"]) {
                    Folder(id: "3", lastChildrenArrayReceivedFromSync: ["5"]) {
                        Bookmark("name", id: "5", url: "url")
                    }
                }
            }
        })
    }

    func testThatBookmarksWithTheSameNameAndURLInDifferentFoldersAreDeduplicatedAndRemoteWins() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark("name", id: "10", url: "url")
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2"]),
            .folder(id: "1"),
            .folder(id: "2", children: ["3"]),
            .bookmark("name", id: "3", url: "url")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2"]) {
            Folder(id: "1", lastChildrenArrayReceivedFromSync: [])
            Folder(id: "2", lastChildrenArrayReceivedFromSync: ["3"]) {
                Bookmark("name", id: "3", url: "url")
            }
        })
    }

    func testThatFavoritesAreMerged() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .favoritesFolder(favorites: ["2"]),
            .mobileFavoritesFolder(favorites: ["2"]),
            .bookmark(id: "2")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2"]) {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
        })

        var favoritesFolder: BookmarkEntity!
        context.performAndWait {
            favoritesFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue, in: context)
        }
        XCTAssertNotNil(favoritesFolder.modifiedAt)
        XCTAssertEqual(favoritesFolder.lastChildrenArrayReceivedFromSync, ["2"])
    }

    func testThatFoldersWithTheSameNameAndParentAreDeduplicated() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("1st level", id: "local1") {
                Folder("2nd level", id: "local2") {
                    Folder("Duplicated folder", id: "local3") {
                        Bookmark(id: "local4")
                    }
                }
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["remote1"]),
            .folder("1st level", id: "remote1", children: ["remote2"]),
            .folder("2nd level", id: "remote2", children: ["remote5"]),
            .folder("Duplicated folder", id: "remote5", children: ["remote6"]),
            .bookmark(id: "remote6")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["remote1"]) {
            Folder("1st level", id: "remote1", lastChildrenArrayReceivedFromSync: ["remote2"]) {
                Folder("2nd level", id: "remote2", lastChildrenArrayReceivedFromSync: ["remote5"]) {
                    Folder("Duplicated folder", id: "remote5", lastChildrenArrayReceivedFromSync: ["remote6"]) {
                        Bookmark(id: "local4")
                        Bookmark(id: "remote6")
                    }
                }
            }
        })
    }

    func testThatFoldersWithTheSameNameAndParentAreDeduplicated2() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("1", id: "local1") {
                Folder("2", id: "local2") {
                    Folder("Duplicated folder", id: "local3") {
                        Folder("4", id: "local4") {
                            Bookmark("5", id: "local5")
                        }
                        Bookmark("6", id: "local6")
                        Bookmark("7", id: "local7")
                        Bookmark("8", id: "local8")
                    }
                }
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["remote1"]),
            .folder("1", id: "remote1", children: ["remote2"]),
            .folder("2", id: "remote2", children: ["remote9"]),
            .folder("Duplicated folder", id: "remote9", children: ["remote10", "remote11", "remote12"]),
            .bookmark(id: "remote10"),
            .bookmark(id: "remote11"),
            .folder(id: "remote12", children: ["remote13"]),
            .bookmark(id: "remote13")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["remote1"]) {
            Folder("1", id: "remote1", lastChildrenArrayReceivedFromSync: ["remote2"]) {
                Folder("2", id: "remote2", lastChildrenArrayReceivedFromSync: ["remote9"]) {
                    Folder("Duplicated folder", id: "remote9", lastChildrenArrayReceivedFromSync: ["remote10", "remote11", "remote12"]) {
                        Folder("4", id: "local4") {
                            Bookmark("5", id: "local5")
                        }
                        Bookmark("6", id: "local6")
                        Bookmark("7", id: "local7")
                        Bookmark("8", id: "local8")
                        Bookmark(id: "remote10")
                        Bookmark(id: "remote11")
                        Folder(id: "remote12", lastChildrenArrayReceivedFromSync: ["remote13"]) {
                            Bookmark(id: "remote13")
                        }
                    }
                }
            }
        })
    }

    func testThatIdenticalBookmarkTreesAreDeduplicated() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("1", id: "1")
            Bookmark("2", id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["11", "12"]),
            .folder("1", id: "11"),
            .bookmark("2", id: "12")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["11", "12"]) {
            Folder("1", id: "11", lastChildrenArrayReceivedFromSync: [])
            Bookmark("2", id: "12")
        })
    }

    func testThatComplexIdenticalBookmarkTreesAreDeduplicated() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "01") {
                Folder(id: "02") {
                    Bookmark(id: "03")
                }
                Bookmark(id: "04")
                Folder(id: "05") {
                    Bookmark(id: "06")
                    Folder(id: "07") {
                        Folder(id: "08")
                        Bookmark(id: "09")
                        Bookmark(id: "10")
                        Bookmark(id: "11")
                    }
                    Bookmark(id: "12")
                    Bookmark(id: "13")
                }
                Bookmark(id: "14")
            }
            Bookmark(id: "15")
            Folder(id: "16") {
                Folder(id: "17") {
                    Bookmark(id: "18")
                }
            }
            Bookmark(id: "19")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["101", "115", "116", "119"]),
            .folder("01", id: "101", children: ["102", "104", "105", "114"]),
            .folder("02", id: "102", children: ["103"]),
            .bookmark("03", id: "103"),
            .bookmark("04", id: "104"),
            .folder("05", id: "105", children: ["106", "107", "112", "113"]),
            .bookmark("06", id: "106"),
            .folder("07", id: "107", children: ["108", "109", "110", "111"]),
            .folder("08", id: "108"),
            .bookmark("09", id: "109"),
            .bookmark("10", id: "110"),
            .bookmark("11", id: "111"),
            .bookmark("12", id: "112"),
            .bookmark("13", id: "113"),
            .bookmark("14", id: "114"),
            .bookmark("15", id: "115"),
            .folder("16", id: "116", children: ["117"]),
            .folder("17", id: "117", children: ["118"]),
            .bookmark("18", id: "118"),
            .bookmark("19", id: "119")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["101", "115", "116", "119"]) {
            Folder("01", id: "101", lastChildrenArrayReceivedFromSync: ["102", "104", "105", "114"]) {
                Folder("02", id: "102", lastChildrenArrayReceivedFromSync: ["103"]) {
                    Bookmark("03", id: "103")
                }
                Bookmark("04", id: "104")
                Folder("05", id: "105", lastChildrenArrayReceivedFromSync: ["106", "107", "112", "113"]) {
                    Bookmark("06", id: "106")
                    Folder("07", id: "107", lastChildrenArrayReceivedFromSync: ["108", "109", "110", "111"]) {
                        Folder("08", id: "108", lastChildrenArrayReceivedFromSync: [])
                        Bookmark("09", id: "109")
                        Bookmark("10", id: "110")
                        Bookmark("11", id: "111")
                    }
                    Bookmark("12", id: "112")
                    Bookmark("13", id: "113")
                }
                Bookmark("14", id: "114")
            }
            Bookmark("15", id: "115")
            Folder("16", id: "116", lastChildrenArrayReceivedFromSync: ["117"]) {
                Folder("17", id: "117", lastChildrenArrayReceivedFromSync: ["118"]) {
                    Bookmark("18", id: "118")
                }
            }
            Bookmark("19", id: "119")
        })
    }

    // MARK: -

    func testWhenRootFolderAndOrphanedFoldersArePresentInResponseThenOrphanedFoldersAreSaved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {}

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2"]),
            .folder(id: "1"),
            .folder(id: "2", children: ["3"]),
            .bookmark("name", id: "3", url: "url"),
            .folder(id: "4", children: ["5"]),
            .bookmark(id: "5")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2"]) {
            Folder(id: "1", lastChildrenArrayReceivedFromSync: [])
            Folder(id: "2", lastChildrenArrayReceivedFromSync: ["3"]) {
                Bookmark("name", id: "3", url: "url")
            }
            Folder(id: "4", isOrphaned: true, lastChildrenArrayReceivedFromSync: ["5"]) {
                Bookmark(id: "5")
            }
        })
    }

    func testThatResponseArrayOrderDoesNotAffectHandling() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {}

        let received: [Syncable] = [
            .bookmark(id: "5"),
            .folder(id: "2", children: ["3"]),
            .folder(id: "4", children: ["5"]),
            .rootFolder(children: ["1", "2"]),
            .bookmark("name", id: "3", url: "url"),
            .folder(id: "1")
        ]

        let rootFolder = try await createEntitiesAndHandleInitialSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2"]) {
            Folder(id: "1", lastChildrenArrayReceivedFromSync: [])
            Folder(id: "2", lastChildrenArrayReceivedFromSync: ["3"]) {
                Bookmark("name", id: "3", url: "url")
            }
            Folder(id: "4", isOrphaned: true, lastChildrenArrayReceivedFromSync: ["5"]) {
                Bookmark(id: "5")
            }
        })
    }

    // MARK: - Helpers

    func createEntitiesAndHandleInitialSyncResponse(
        with bookmarkTree: BookmarkTree,
        received: [Syncable],
        clientTimestamp: Date = Date(),
        serverTimestamp: String = "1234",
        in context: NSManagedObjectContext
    ) async throws -> BookmarkEntity {

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        var rootFolder: BookmarkEntity!

        context.performAndWait {
            context.refreshAllObjects()
            rootFolder = BookmarkUtils.fetchRootFolder(context)
        }

        return rootFolder
    }
}
