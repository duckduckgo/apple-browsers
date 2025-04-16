//
//  BookmarksRegularSyncResponseHandlerTests.swift
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

final class BookmarksRegularSyncResponseHandlerTests: BookmarksProviderTestsBase {

    func testThatBookmarksAreReorderedWithinFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.rootFolder(children: ["2", "1"])]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2", "1"]) {
            Bookmark(id: "2")
            Bookmark(id: "1")
        })
    }

    func testThatNewBookmarkIsAppendedToFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
        })
    }

    func testWhenRootFolderIsMissingLocalBookmarksThenTheyBecomeOrphaned() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3"]) {
            Bookmark(id: "1", isOrphaned: true)
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3")
        })
    }

    func testWhenSubfolderIsMissingLocalBookmarksThenTheyBecomeOrphaned() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark(id: "2")
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .folder(id: "1", children: ["4"]),
            .bookmark(id: "4")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Folder(id: "1", lastChildrenArrayReceivedFromSync: ["4"]) {
                Bookmark(id: "4")
            }
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3", isOrphaned: true)
        })
    }

    func testThatNewFavoritesAreAppended() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .favoritesFolder(favorites: ["1", "2", "3"]),
            .mobileFavoritesFolder(favorites: ["1", "2", "3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.mobile, .unified])
        })
    }

    func testThatFavoritesInSubfoldersAreAppended() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Folder(id: "2") {
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .favoritesFolder(favorites: ["1", "3"]),
            .mobileFavoritesFolder(favorites: ["1", "3"]),
            .folder(id: "2", children: ["3"]),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Folder(id: "2", lastChildrenArrayReceivedFromSync: ["3"]) {
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            }
        })
    }

    func testWhenPayloadContainsEmptyFavoritesFolderThenAllFavoritesAreRemoved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Folder(id: "2") {
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            }
        }

        let received: [Syncable] = [
            .favoritesFolder(favorites: []),
            .mobileFavoritesFolder(favorites: [])
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Folder(id: "2") {
                Bookmark(id: "3")
            }
        })
    }

    func testWhenPayloadDoesNotContainFavoritesFolderThenFavoritesAreNotAffected() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Folder(id: "2") {
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "4"]),
            .bookmark(id: "4")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "4"]) {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Folder(id: "2") {
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            }
            Bookmark(id: "4")
        })
    }

    func testThatSinglePayloadCanCreateReorderAndOrphanBookmarks() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3", "2"]),
            .bookmark(id: "2"),
            .bookmark(id: "3")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3", "2"]) {
            Bookmark(id: "1", isOrphaned: true)
            Bookmark(id: "3")
            Bookmark(id: "2")
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

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
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

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
        })
    }

    func testThatSinglePayloadCanDeleteCreateReorderAndOrphanBookmarks() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3", "remote2", "4"]),
            .bookmark(id: "1", isDeleted: true),
            .bookmark("2", id: "remote2"),
            .bookmark(id: "3"),
            .bookmark(id: "4")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3", "remote2", "4"]) {
            Bookmark(id: "3")
            Bookmark("2", id: "remote2")
            Bookmark(id: "4")
            Bookmark(id: "2", isOrphaned: true)
        })
    }

    // MARK: - Responses with subtree

    func testWhenRootFolderIsNotPresentInResponseThenBookmarkCanBeAddedToSubfolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3") {
                Bookmark("title", id: "4", url: "url")
            }
        }

        let received: [Syncable] = [
            .folder(id: "3", children: ["5", "4"]),
            .bookmark("title", id: "5", url: "url")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3", lastChildrenArrayReceivedFromSync: ["5", "4"]) {
                Bookmark("title", id: "5", url: "url")
                Bookmark("title", id: "4", url: "url")
            }
        })
    }

    func testWhenRootFolderIsNotPresentInResponseThenBookmarkCanBeMovedBetweenSubfolders() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3") {
                Folder(id: "4") {
                    Bookmark("title", id: "5", url: "url")
                }
                Folder(id: "6") {
                    Bookmark("title2", id: "7", url: "url2")
                }
            }
        }

        let received: [Syncable] = [
            .folder(id: "6", children: ["5"]),
            .bookmark("title", id: "5", url: "url")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3") {
                Folder(id: "4")
                Folder(id: "6", lastChildrenArrayReceivedFromSync: ["5"]) {
                    Bookmark("title", id: "5", url: "url")
                }
            }
            Bookmark("title2", id: "7", url: "url2", isOrphaned: true)
        })
    }

    func testWhenRootFolderIsNotPresentInResponseThenChangesToMultipleSubtreesAreSupported() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3") {
                Folder(id: "4") {
                    Bookmark("title5", id: "5", url: "url5")
                }
                Folder(id: "6") {
                    Bookmark("title7", id: "7", url: "url7")
                }
            }
            Folder(id: "8") {
                Bookmark("title9", id: "9", url: "url9")
                Bookmark("title10", id: "10", url: "url10")
            }
            Folder(id: "11") {
                Bookmark("title12", id: "12", url: "url12")
                Bookmark("title13", id: "13", url: "url13")
            }
            Folder(id: "14") {
                Bookmark("title15", id: "15", url: "url15")
                Bookmark("title16", id: "16", url: "url16")
            }
        }

        let received: [Syncable] = [
            .folder(id: "3", children: ["6", "4"]),
            .folder(id: "8", children: ["10", "9"]),
            .folder(id: "11", children: ["12", "14", "13"]),
            .folder(id: "14", children: ["18", "15", "16"]),
            .bookmark("title16", id: "18", url: "url16")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3", lastChildrenArrayReceivedFromSync: ["6", "4"]) {
                Folder(id: "6") {
                    Bookmark("title7", id: "7", url: "url7")
                }
                Folder(id: "4") {
                    Bookmark("title5", id: "5", url: "url5")
                }
            }
            Folder(id: "8", lastChildrenArrayReceivedFromSync: ["10", "9"]) {
                Bookmark("title10", id: "10", url: "url10")
                Bookmark("title9", id: "9", url: "url9")
            }
            Folder(id: "11", lastChildrenArrayReceivedFromSync: ["12", "14", "13"]) {
                Bookmark("title12", id: "12", url: "url12")
                Folder(id: "14", lastChildrenArrayReceivedFromSync: ["18", "15", "16"]) {
                    Bookmark("title16", id: "18", url: "url16")
                    Bookmark("title15", id: "15", url: "url15")
                    Bookmark("title16", id: "16", url: "url16")
                }
                Bookmark("title13", id: "13", url: "url13")
            }
        })
    }

    func testWhenRootFolderIsNotPresentInResponseThenBookmarksAreAppendedToFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("Folder", id: "1") {
                Bookmark(id: "2")
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .folder("Folder", id: "1", children: ["2", "3", "5", "6"]),
            .bookmark(id: "5"),
            .bookmark(id: "6")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Folder("Folder", id: "1", lastChildrenArrayReceivedFromSync: ["2", "3", "5", "6"]) {
                Bookmark(id: "2")
                Bookmark(id: "3")
                Bookmark(id: "5")
                Bookmark(id: "6")
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

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
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

    // MARK: - Responses with parts of data structure missing

    func testWhenChildIsMissingAndReceivedLaterThenRelationIsPersisted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {}

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2"]),
            .favoritesFolder(favorites: ["1", "2", "3"]),
            .mobileFavoritesFolder(favorites: ["1"]),
            .desktopFavoritesFolder(favorites: ["2", "3"])
        ]

        _ = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)

        let received2: [Syncable] = [
            .bookmark(id: "1"),
            .bookmark(id: "2"),
            .bookmark(id: "3"),
        ]

        let root = try await handleSyncResponse(received: received2, in: context)

        context.performAndWait {
            XCTAssertEqual(root.childrenArray.count, 2)

            let unified = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue, in: context)
            XCTAssertEqual(Set((unified?.favoritesArray.map { $0.uuid }) ?? []), Set(["1", "2", "3"]))

            let mobile = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.mobile.rawValue, in: context)
            XCTAssertEqual(Set((mobile?.favoritesArray.map { $0.uuid }) ?? []), Set(["1"]))

            let desktop = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.desktop.rawValue, in: context)
            XCTAssertEqual(Set((desktop?.favoritesArray.map { $0.uuid }) ?? []), Set(["2", "3"]))
        }
    }

    // MARK: - Handling Decryption Failures
    func testThatDecryptionFailureDoesntAffectBookmarksOrCrash() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.rootFolder(children: ["3", "4"])]

        crypter.throwsException(exceptionString: "ddgSyncDecrypt failed: invalid ciphertext length: X")

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: nil) {
            Bookmark(id: "1")
            Bookmark(id: "2")
        })

        crypter.throwsException(exceptionString: nil)
    }

    // MARK: - Handling Orphans

    func testWhenOrphanedBookmarkIsReceivedThenItIsSaved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [.bookmark(id: "3")]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3", isOrphaned: true)
        })
    }

    func testWhenOrphanedFolderIsReceivedThenItIsSaved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .folder(id: "3", children: ["4"]),
            .bookmark(id: "4")
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "3", isOrphaned: true, lastChildrenArrayReceivedFromSync: ["4"]) {
                Bookmark(id: "4")
            }
        })
    }

    // MARK: - Invalid Favorites Form Factors

    func testWhenMobileOnlyFavoriteIsReceivedThenItIsSaved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .mobileFavoritesFolder(favorites: ["1"])
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile])
            Bookmark(id: "2")
        })
    }

    func testWhenUnifiedOnlyFavoriteIsReceivedThenItIsSaved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .favoritesFolder(favorites: ["1"])
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.unified])
            Bookmark(id: "2")
        })
    }

    func testWhenNonUnifiedFavoriteIsReceivedThenItIsSaved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .mobileFavoritesFolder(favorites: ["1"]),
            .desktopFavoritesFolder(favorites: ["1", "2"])
        ]

        let rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .desktop])
            Bookmark(id: "2", favoritedOn: [.desktop])
        })
    }

    // MARK: - Last Children Array Received From Sync

    func testThatLastChildrenArrayIsUpdatedAfterEveryHandledResponse() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        var received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]),
            .bookmark(id: "3")
        ]

        var rootFolder = try await createEntitiesAndHandleSyncResponse(with: bookmarkTree, received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
        })

        received = [
            .rootFolder(children: ["1", "2", "4", "3"]),
            .folder(id: "4", children: ["5", "6"]),
            .bookmark(id: "3"),
            .bookmark(id: "5"),
            .bookmark(id: "6")
        ]

        rootFolder = try await handleSyncResponse(received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "4", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "4", lastChildrenArrayReceivedFromSync: ["5", "6"]) {
                Bookmark(id: "5")
                Bookmark(id: "6")
            }
            Bookmark(id: "3")
        })

        received = [
            .rootFolder(children: ["3", "4"]),
            .folder(id: "4", children: ["6"]),
            .bookmark(id: "1", isDeleted: true),
            .bookmark(id: "2", isDeleted: true),
            .bookmark(id: "5", isDeleted: true)
        ]

        rootFolder = try await handleSyncResponse(received: received, in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3", "4"]) {
            Bookmark(id: "3")
            Folder(id: "4", lastChildrenArrayReceivedFromSync: ["6"]) {
                Bookmark(id: "6")
            }
        })
    }

    // MARK: - Helpers

    func createEntitiesAndHandleSyncResponse(
        with bookmarkTree: BookmarkTree,
        sent: [Syncable] = [],
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

        return try await handleSyncResponse(
            sent: sent,
            received: received,
            clientTimestamp: clientTimestamp,
            serverTimestamp: serverTimestamp,
            in: context
        )
    }

    func handleSyncResponse(
        sent: [Syncable] = [],
        received: [Syncable],
        clientTimestamp: Date = Date(),
        serverTimestamp: String = "1234",
        in context: NSManagedObjectContext
    ) async throws -> BookmarkEntity {

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        var rootFolder: BookmarkEntity!

        context.performAndWait {
            context.refreshAllObjects()
            rootFolder = BookmarkUtils.fetchRootFolder(context)
        }

        return rootFolder
    }
}
