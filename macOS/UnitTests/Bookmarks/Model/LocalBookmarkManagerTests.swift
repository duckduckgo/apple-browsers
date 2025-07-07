//
//  LocalBookmarkManagerTests.swift
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

import Bookmarks
import Combine
import Foundation
import os.log
import Utilities

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class LocalBookmarkManagerTests: XCTestCase {

    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!
    var foldersStore: BookmarkFolderStoreMock!

    enum BookmarkManagerError: Error {
        case somethingReallyBad
    }

    override func setUp() {
        container = CoreData.bookmarkContainer()
        let context = container.newBackgroundContext()
        self.context = context
        Logger.tests.debug("LocalBookmarkManagerTests.\(self.name).setUp with \(context.description, privacy: .public)")

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
        }
    }

    override func tearDown() {
        // flush pending operations
        Logger.tests.debug("LocalBookmarkManagerTests.\(self.name).tearDown: flush")
        context.performAndWait { }
        context = nil
        container = nil
        Logger.tests.debug("LocalBookmarkManagerTests.\(self.name).tearDown end")
    }

    // MARK: - Tests

    @MainActor
    func testWhenBookmarksAreNotLoadedYet_ThenManagerIgnoresBookmarkingRequests() async {
        let (bookmarkManager, _) = await manager(loadBookmarks: false) {}

        XCTAssertNil(bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Test", isFavorite: false))
        XCTAssertNil(bookmarkManager.updateUrl(of: Bookmark.aBookmark, to: URL.duckDuckGoAutocomplete))
    }

    @MainActor
    func testWhenBookmarksAreLoaded_ThenTheManagerHoldsAllLoadedBookmarks() async {
        let (bookmarkManager, bookmarkStoreMock) = await manager {
            Bookmark.aBookmark
        }

        XCTAssert(bookmarkManager.isUrlBookmarked(url: Bookmark.aBookmark.urlObject!))
        XCTAssertNotNil(bookmarkManager.getBookmark(for: Bookmark.aBookmark.urlObject!))
        XCTAssert(bookmarkStoreMock.loadAllCalled)
        XCTAssertEqual(bookmarkManager.list?.bookmarks().count, 1)
    }

    @MainActor
    func testWhenLoadFails_ThenTheManagerHoldsBookmarksAreNil() {
        let bookmarkStoreMock = BookmarkStoreMock()
        let bookmarkManager = LocalBookmarkManager(bookmarkStore: bookmarkStoreMock, appearancePreferences: .mock)

        bookmarkStoreMock.loadError = BookmarkManagerError.somethingReallyBad
        bookmarkManager.loadBookmarks()

        XCTAssertNil(bookmarkManager.list?.bookmarks())
        XCTAssert(bookmarkStoreMock.loadAllCalled)
    }

    @MainActor
    func testWhenBookmarkIsCreated_ThenManagerSavesItToStore() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!

        XCTAssert(bookmarkManager.isUrlBookmarked(url: bookmark.urlObject!))
        XCTAssert(bookmarkStoreMock.saveBookmarkCalled)
    }

    @MainActor
    func testWhenBookmarkIsCreatedAndStoringFails_ThenManagerRemovesItFromList() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()

        bookmarkStoreMock.saveEntitiesError = BookmarkManagerError.somethingReallyBad
        let bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!

        XCTAssertFalse(bookmarkManager.isUrlBookmarked(url: bookmark.urlObject!))
        XCTAssert(bookmarkStoreMock.saveBookmarkCalled)
    }

    @MainActor
    func testWhenUrlIsAlreadyBookmarked_ThenManagerReturnsNil() async {
        let (bookmarkManager, _) = await aManager()
        _ = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!

        XCTAssertNil(bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false))
    }

    @MainActor
    func testWhenBookmarkIsRemoved_ThenManagerRemovesItFromStore() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!

        bookmarkManager.remove(bookmark: bookmark, undoManager: nil)

        XCTAssertFalse(bookmarkManager.isUrlBookmarked(url: bookmark.urlObject!))
        XCTAssert(bookmarkStoreMock.saveBookmarkCalled)
        XCTAssert(bookmarkStoreMock.removeCalled)
    }

    @MainActor
    func testWhenFolderIsRemoved_ThenManagerRemovesItFromStore() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        var folder: BookmarkFolder!
        let e = expectation(description: "Folder created")
        bookmarkManager.makeFolder(named: "Folder", parent: nil) { result in
            folder = try? result.get()
            e.fulfill()
        }
        await fulfillment(of: [e], timeout: 1)
        guard let folder else { XCTFail("Folder not loaded"); return }

        let loadedFolder = bookmarkManager.getBookmarkFolder(withId: folder.id)
        XCTAssertEqual(folder, loadedFolder)

        bookmarkManager.remove(folder: folder, undoManager: nil)

        XCTAssertNil(bookmarkManager.getBookmarkFolder(withId: folder.id))
        XCTAssert(bookmarkStoreMock.saveFolderCalled)
        XCTAssertEqual(bookmarkStoreMock.removeCalledWithIds, [folder.id])
    }

    @MainActor
    func testWhenBookmarkAndFolderAreRemoved_ThenManagerRemovesThemFromStore() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!
        var folder: BookmarkFolder!
        let e = expectation(description: "Folder created")
        bookmarkManager.makeFolder(named: "Folder", parent: nil) { result in
            folder = try? result.get()
            e.fulfill()
        }
        await fulfillment(of: [e], timeout: 1)
        guard let folder else { XCTFail("Folder not loaded"); return }

        bookmarkManager.remove(objectsWithUUIDs: [folder.id, bookmark.id], undoManager: nil)

        XCTAssertEqual(Set(bookmarkStoreMock.removeCalledWithIds ?? []), Set([folder.id, bookmark.id]))
    }

    @MainActor
    func testWhenRemovalFails_ThenManagerPutsBookmarkBackToList() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!

        bookmarkStoreMock.removeError = BookmarkManagerError.somethingReallyBad
        bookmarkManager.remove(bookmark: bookmark, undoManager: nil)

        XCTAssert(bookmarkManager.isUrlBookmarked(url: bookmark.urlObject!))
        XCTAssert(bookmarkStoreMock.saveBookmarkCalled)
        XCTAssert(bookmarkStoreMock.removeCalled)
    }

    @MainActor
    func testWhenBookmarkRemovalIsUndone_ThenRestoreBookmarkIsCalled() async throws {
        let (bookmarkManager, bookmarkStoreMock) = await manager(with: {
            bookmark(.duckDuckGo)
            bookmark(.duckDuckGoEmail)
            folder("Folder")
        })
        let undoManager = UndoManager()
        let removedBookmark = bookmarkManager.getBookmark(for: .duckDuckGoEmail)!

        // remove
        bookmarkManager.remove(bookmark: removedBookmark, undoManager: undoManager)
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 2 }.timeout(1).first().promise().get()

        // undo remove
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 3 }.timeout(1).first().promise().get()

        assertEqual(bookmarkStoreMock.saveEntitiesAtIndicesCalledWith, [(removedBookmark, 1, nil)])
        // update the bookmark because it‘s recreated with a new id
        guard let removedBookmark = bookmarkManager.getBookmark(for: .duckDuckGoEmail) else { XCTFail("Could not fetch bookmark"); return }

        // redo remove
        bookmarkStoreMock.removeCalledWithIds = nil
        XCTAssertTrue(undoManager.canRedo)

        // validate bookmark is removed
        undoManager.redo()
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 2 }.timeout(1).first().promise().get()
        XCTAssertEqual(bookmarkStoreMock.removeCalledWithIds ?? [], [removedBookmark.id])

        // undo again
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()

        assertEqual(bookmarkStoreMock.saveEntitiesAtIndicesCalledWith, [(removedBookmark, 1, nil)])
        XCTAssertTrue(undoManager.canRedo)
    }

    @MainActor
    func testWhenFolderRemovalIsUndone_ThenRestoreFolderIsCalled() async throws {
        let (bookmarkManager, bookmarkStoreMock) = await manager(with: {
            bookmark(.duckDuckGo)
            folder(id: "1", "Folder") {
                bookmark(.duckDuckGoEmailLogin)
                bookmark(.duckDuckGoEmailInfo, isFavorite: true)
                folder("Subfolder") {
                    bookmark(.duckDuckGoAutocomplete, isFavorite: true)
                    bookmark(.aboutDuckDuckGo, isFavorite: false)
                }
            }
            bookmark(.duckDuckGoEmail)
        })
        let undoManager = UndoManager()
        let removedFolder = bookmarkManager.getBookmarkFolder(withId: "1")!

        // remove
        bookmarkManager.remove(folder: removedFolder, undoManager: undoManager)
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 2 }.timeout(1).first().promise().get()

        // undo remove
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 3 }.timeout(1).first().promise().get()

        // validate entities are restored
        guard let removedFolder1 = bookmarkStoreMock.saveEntitiesAtIndicesCalledWith?[safe: 0]?.entity as? BookmarkFolder,
              let removedFolder2 = bookmarkStoreMock.saveEntitiesAtIndicesCalledWith?[safe: 3]?.entity as? BookmarkFolder else {
            XCTFail("1. Could not fetch folder")
            return
        }
        assertEqual(bookmarkStoreMock.saveEntitiesAtIndicesCalledWith, [
            (removedFolder1, 1, nil),
            (Bookmark(.duckDuckGoEmailLogin, parentId: removedFolder1.id), nil, nil),
            (Bookmark(.duckDuckGoEmailInfo, isFavorite: true, parentId: removedFolder1.id), nil, nil),
            (removedFolder2, nil, nil),
            (Bookmark(.duckDuckGoAutocomplete, isFavorite: true, parentId: removedFolder2.id), nil, nil),
            (Bookmark(.aboutDuckDuckGo, isFavorite: false, parentId: removedFolder2.id), nil, nil),
        ])

        // redo remove
        bookmarkStoreMock.removeCalledWithIds = nil
        XCTAssertTrue(undoManager.canRedo)

        // validate bookmark is removed
        undoManager.redo()
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 2 }.timeout(1).first().promise().get()
        XCTAssertEqual(bookmarkStoreMock.removeCalledWithIds ?? [], [removedFolder1.id])

        // undo again
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()

        // validate entities are restored
        guard let removedFolder1 = bookmarkStoreMock.saveEntitiesAtIndicesCalledWith?[safe: 0]?.entity as? BookmarkFolder,
              let removedFolder2 = bookmarkStoreMock.saveEntitiesAtIndicesCalledWith?[safe: 3]?.entity as? BookmarkFolder else {
            XCTFail("2. Could not fetch folder")
            return
        }
        assertEqual(bookmarkStoreMock.saveEntitiesAtIndicesCalledWith, [
            (removedFolder1, 1, nil),
            (Bookmark(.duckDuckGoEmailLogin, parentId: removedFolder1.id), nil, nil),
            (Bookmark(.duckDuckGoEmailInfo, isFavorite: true, parentId: removedFolder1.id), nil, nil),
            (removedFolder2, nil, nil),
            (Bookmark(.duckDuckGoAutocomplete, isFavorite: true, parentId: removedFolder2.id), nil, nil),
            (Bookmark(.aboutDuckDuckGo, isFavorite: false, parentId: removedFolder2.id), nil, nil),
        ])
        XCTAssertTrue(undoManager.canRedo)
    }

    @MainActor
    func testWhenBookmarkAndFolderRemovalIsUndone_ThenRestoreEntitiesIsCalled() async throws {
        let (bookmarkManager, bookmarkStoreMock) = await manager(with: {
            bookmark(.duckDuckGo)
            bookmark(.aboutDuckDuckGo)
            folder(id: "1", "Folder") {
                bookmark(.duckDuckGoEmailLogin)
                bookmark(.duckDuckGoEmailInfo, isFavorite: true)
                folder(id: "2", "Subfolder") {
                    bookmark(.duckDuckGoAutocomplete, isFavorite: true)
                }
            }
            bookmark(.duckDuckGoEmail)
            folder(id: "3", "Folder 2") {
                bookmark(.ddgLearnMore, isFavorite: false)
            }
            bookmark(.duckDuckGoMorePrivacyInfo)
        })
        let undoManager = UndoManager()
        let removedEntities = [
            bookmarkManager.getBookmarkFolder(withId: "3")!,
            bookmarkManager.getBookmark(for: .duckDuckGoEmail)!,
            bookmarkManager.getBookmark(for: .duckDuckGo)!,
            bookmarkManager.getBookmarkFolder(withId: "1")!,
            bookmarkManager.getBookmark(for: .duckDuckGoMorePrivacyInfo)!,
        ] as [BaseBookmarkEntity]

        bookmarkManager.remove(objectsWithUUIDs: removedEntities.map(\.id), undoManager: undoManager)
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 1 }.timeout(1).first().promise().get()

        // undo remove
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 6 }.timeout(1).first().promise().get()

        // validate entities are restored
        guard let removedFolder1 = bookmarkStoreMock.savedFolder(withTitle: "Folder") else { return XCTFail("1. Could not fetch Folder") }
        guard let removedFolder2 = bookmarkStoreMock.savedFolder(withTitle: "Subfolder") else { return XCTFail("1. Could not fetch Subfolder") }
        guard let removedFolder3 = bookmarkStoreMock.savedFolder(withTitle: "Folder 2") else { return XCTFail("1. Could not fetch Folder 2") }
        assertEqual(bookmarkStoreMock.saveEntitiesAtIndicesCalledWith, [
            (Bookmark(.duckDuckGo), 0, nil),
            (removedFolder1, 2, nil),
            (Bookmark(.duckDuckGoEmail), 3, nil),
            (removedFolder3, 4, nil),
            (Bookmark(.duckDuckGoMorePrivacyInfo, isFavorite: false), 5, nil),
            (Bookmark(.duckDuckGoEmailLogin, parentId: removedFolder1.id), nil, nil),
            (Bookmark(.duckDuckGoEmailInfo, isFavorite: true, parentId: removedFolder1.id), nil, nil),
            (removedFolder2, nil, nil),
            (Bookmark(.duckDuckGoAutocomplete, isFavorite: true, parentId: removedFolder2.id), nil, nil),
            (Bookmark(.ddgLearnMore, isFavorite: false, parentId: removedFolder3.id), nil, nil),
        ])

        // redo remove
        bookmarkStoreMock.removeCalledWithIds = nil
        XCTAssertTrue(undoManager.canRedo)

        // validate bookmark is removed
        undoManager.redo()
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 1 }.timeout(1).first().promise().get()
        XCTAssertEqual(bookmarkStoreMock.removeCalledWithIds?.count, 5)

        // undo again
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 6 }.timeout(1).first().promise().get()

        // validate entities are restored
        guard let removedFolder1 = bookmarkStoreMock.savedFolder(withTitle: "Folder") else { return XCTFail("2. Could not fetch Folder") }
        guard let removedFolder2 = bookmarkStoreMock.savedFolder(withTitle: "Subfolder") else { return XCTFail("2. Could not fetch Subfolder") }
        guard let removedFolder3 = bookmarkStoreMock.savedFolder(withTitle: "Folder 2") else { return XCTFail("2. Could not fetch Folder 2") }
        assertEqual(bookmarkStoreMock.saveEntitiesAtIndicesCalledWith, [
            (Bookmark(.duckDuckGo), 0, nil),
            (removedFolder1, 2, nil),
            (Bookmark(.duckDuckGoEmail), 3, nil),
            (removedFolder3, 4, nil),
            (Bookmark(.duckDuckGoMorePrivacyInfo, isFavorite: false), 5, nil),
            (Bookmark(.duckDuckGoEmailLogin, parentId: removedFolder1.id), nil, nil),
            (Bookmark(.duckDuckGoEmailInfo, isFavorite: true, parentId: removedFolder1.id), nil, nil),
            (removedFolder2, nil, nil),
            (Bookmark(.duckDuckGoAutocomplete, isFavorite: true, parentId: removedFolder2.id), nil, nil),
            (Bookmark(.ddgLearnMore, isFavorite: false, parentId: removedFolder3.id), nil, nil),
        ])
        XCTAssertTrue(undoManager.canRedo)
    }

    // Validate bookmark ordering indexes adjustment considering deleted and stub records
    func testInsertionIndicesAdjustment() {
        let collection1: [Int?] = [nil, 100, 200, 300]
        let indices1: IndexSet = [0, 1, 2, 3, 4, 5]
        let adjusted1 = collection1.adjustInsertionIndices(indices1, isCountedItem: { $0 != nil }).enumerated().map { (indices1.map(\.self)[$0.offset], $0.element) }
        let result1 = adjusted1.reduce(into: collection1) { $0.insert($1.0, at: $1.1) }
        XCTAssertEqual(result1, [nil, 0, 1, 2, 3, 4, 5, 100, 200, 300])

        let collection2: [Int?] = [100, 200, nil, nil, 300, 400, nil, nil, 500]
        let indices2: IndexSet = [2, 3, 6, 7, 9, 10, 11]
        let adjusted2 = collection2.adjustInsertionIndices(indices2, isCountedItem: { $0 != nil }).enumerated().map { (indices2.map(\.self)[$0.offset], $0.element) }
        let result2 = adjusted2.reduce(into: collection2) { $0.insert($1.0, at: $1.1) }
        XCTAssertEqual(result2, [100, 200, nil, nil, 2, 3, 300, 400, nil, nil, 6, 7, 500, 9, 10, 11])

        let collection3: [Int?] = []
        let indices3: IndexSet = [0, 1, 2]
        let adjusted3 = collection3.adjustInsertionIndices(indices3, isCountedItem: { $0 != nil }).enumerated().map { (indices3.map(\.self)[$0.offset], $0.element) }
        let result3 = adjusted3.reduce(into: collection3) { $0.insert($1.0, at: $1.1) }
        XCTAssertEqual(result3, [0, 1, 2])

        let collection4: [Int?] = [100, 200, 300]
        let indices4: IndexSet = [0, 2, 4, 6, 7]
        let adjusted4 = collection4.adjustInsertionIndices(indices4, isCountedItem: { $0 != nil }).enumerated().map { (indices4.map(\.self)[$0.offset], $0.element) }
        let result4 = adjusted4.reduce(into: collection4) { $0.insert($1.0, at: $1.1) }
        XCTAssertEqual(result4, [0, 100, 2, 200, 4, 300, 6, 7])

        let collection5: [Int?] = [100, 200, nil, nil, nil, 300, 400, nil, nil, nil, 500]
        let indices5: IndexSet = [0, 2, 3, 6, 7, 9, 10, 11, 13, 14]
        let adjusted5 = collection5.adjustInsertionIndices(indices5, isCountedItem: { $0 != nil }).enumerated().map { (indices5.map(\.self)[$0.offset], $0.element) }
        let result5 = adjusted5.reduce(into: collection5) { $0.insert($1.0, at: $1.1) }
        XCTAssertEqual(result5, [0, 100, 2, 3, 200, nil, nil, nil, 300, 6, 7, 400, nil, nil, nil, 9, 10, 11, 500, 13, 14])
    }

    @MainActor
    func testWhenBookmarkMovedAfterRestoration_ThenMovePositionIsCorrect() async throws {
        // create bookmarks
        let bookmarks: [BaseBookmarkEntity] = [
            BookmarkFolder("Folder 1"),
            BookmarkFolder("Folder 2"),
            Bookmark(.duckDuckGo.appending("1")),
            Bookmark(.duckDuckGo.appending("2")),
            Bookmark(.duckDuckGo.appending("3")),
            Bookmark(.duckDuckGo.appending("4")),
            Bookmark(.duckDuckGo.appending("5")),
            Bookmark(.duckDuckGo.appending("6")),
            Bookmark(.duckDuckGo.appending("7")),
            Bookmark(.duckDuckGo.appending("8")),
        ]
        let (bookmarkManager, _) = await manager(with: { bookmarks })

        let undoManager = UndoManager()
        let removedEntities = [
            bookmarkManager.getBookmark(for: .duckDuckGo.appending("1"))!,
            bookmarkManager.getBookmark(for: .duckDuckGo.appending("4"))!,
            bookmarkManager.getBookmark(for: .duckDuckGo.appending("5"))!,
            bookmarkManager.getBookmark(for: .duckDuckGo.appending("7"))!,
        ] as [BaseBookmarkEntity]

        // remove bookmarks at random positions
        bookmarkManager.remove(objectsWithUUIDs: removedEntities.map(\.id), undoManager: undoManager)
        _=try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 6 }.timeout(1).first().promise().get()

        // undo remove
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()

        let updatedBookmarks = try await bookmarkManager.$list.filter { $0?.topLevelEntities.count == 10 }.timeout(1).first().promise().get()?.topLevelEntities ?? []
        for idx in 0..<max(bookmarks.count, updatedBookmarks.count) {
            XCTAssert(updatedBookmarks[safe: idx]?.matches(bookmarks[safe: idx]) == true, "#\(idx): \(updatedBookmarks[safe: idx]?.debugDescription ?? "<nil>") ≠ \(bookmarks[safe: idx]?.debugDescription ?? "<nil>")")
        }

        guard let bookmark1 = bookmarkManager.getBookmark(for: .duckDuckGo.appending("1")) else { return XCTFail("Could not fetch Bookmark 1") }
        guard let bookmark2 = bookmarkManager.getBookmark(for: .duckDuckGo.appending("2")) else { return XCTFail("Could not fetch Bookmark 2") }
        guard let bookmark4 = bookmarkManager.getBookmark(for: .duckDuckGo.appending("4")) else { return XCTFail("Could not fetch Bookmark 4") }
        guard let bookmark5 = bookmarkManager.getBookmark(for: .duckDuckGo.appending("5")) else { return XCTFail("Could not fetch Bookmark 5") }
        guard let bookmark7 = bookmarkManager.getBookmark(for: .duckDuckGo.appending("7")) else { return XCTFail("Could not fetch Bookmark 7") }

        // reorder a removed bookmark to some position close to the end of the list
        bookmarkManager.move(objectUUIDs: [bookmark1.id], toIndex: 9, withinParentFolder: .root)
        bookmarkManager.move(objectUUIDs: [bookmark4.id], toIndex: 10, withinParentFolder: .root)
        bookmarkManager.move(objectUUIDs: [bookmark7.id], toIndex: 0, withinParentFolder: .root)
        bookmarkManager.move(objectUUIDs: [bookmark5.id], toIndex: 8, withinParentFolder: .root)
        bookmarkManager.move(objectUUIDs: [bookmark4.id], toIndex: 2, withinParentFolder: .root)
        bookmarkManager.move(objectUUIDs: [bookmark2.id], toIndex: 6, withinParentFolder: .root)
        let result = try await bookmarkManager.$list.dropFirst(6).timeout(1).first().promise().get()?.topLevelEntities ?? []

        // validate order
        let expectedBookmarks = [
            Bookmark(.duckDuckGo.appending("7")),
            BookmarkFolder("Folder 1"),
            Bookmark(.duckDuckGo.appending("4")),
            BookmarkFolder("Folder 2"),
            Bookmark(.duckDuckGo.appending("3")),
            Bookmark(.duckDuckGo.appending("2")),
            Bookmark(.duckDuckGo.appending("6")),
            Bookmark(.duckDuckGo.appending("1")),
            Bookmark(.duckDuckGo.appending("5")),
            Bookmark(.duckDuckGo.appending("8")),
        ]
        for idx in 0..<max(expectedBookmarks.count, result.count) {
            XCTAssert(result[safe: idx]?.matches(expectedBookmarks[safe: idx]) == true, "#\(idx): \(result[safe: idx]?.debugDescription ?? "<nil>") ≠ \(expectedBookmarks[safe: idx]?.debugDescription ?? "<nil>")")
        }
    }

    @MainActor
    func testWhenBookmarkNoLongerExist_ThenManagerIgnoresAttemptToRemoval() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()

        bookmarkManager.remove(bookmark: Bookmark.aBookmark, undoManager: nil)

        XCTAssertFalse(bookmarkManager.isUrlBookmarked(url: Bookmark.aBookmark.urlObject!))
        XCTAssertFalse(bookmarkStoreMock.removeCalled)
    }

    @MainActor
    func testWhenBookmarkNoLongerExist_ThenManagerIgnoresAttemptToUpdate() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()

        bookmarkManager.update(bookmark: Bookmark.aBookmark)
        let updateUrlResult = bookmarkManager.updateUrl(of: Bookmark.aBookmark, to: URL.duckDuckGoAutocomplete)

        XCTAssertFalse(bookmarkManager.isUrlBookmarked(url: Bookmark.aBookmark.urlObject!))
        XCTAssertFalse(bookmarkStoreMock.updateBookmarkCalled)
        XCTAssertNil(updateUrlResult)
    }

    @MainActor
    func testWhenBookmarkIsUpdated_ThenManagerUpdatesItInStore() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!

        bookmark.isFavorite = !bookmark.isFavorite
        bookmarkManager.update(bookmark: bookmark)

        XCTAssert(bookmarkManager.isUrlBookmarked(url: bookmark.urlObject!))
        XCTAssert(bookmarkStoreMock.updateBookmarkCalled)
    }

    @MainActor
    func testWhenBookmarkUrlIsUpdated_ThenManagerUpdatesItAlsoInStore() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false)!

        let newURL = URL.duckDuckGoAutocomplete
        guard let newBookmark = bookmarkManager.updateUrl(of: bookmark, to: newURL) else {
            XCTFail("bookmark not saved")
            return
        }

        XCTAssertFalse(bookmarkManager.isUrlBookmarked(url: bookmark.urlObject!))
        XCTAssert(bookmarkManager.isUrlBookmarked(url: newBookmark.urlObject!))
        XCTAssert(bookmarkManager.isUrlBookmarked(url: newURL))
        XCTAssert(bookmarkStoreMock.updateBookmarkCalled)
    }

    @MainActor
    func testWhenBookmarkFolderIsUpdatedAndMoved_ThenManagerUpdatesItAlsoInStore() async throws {
        let parent = BookmarkFolder(id: "1", title: "Parent")
        let folder = BookmarkFolder(id: "2", title: "Child")
        let (bookmarkManager, bookmarkStoreMock) = await manager {
            parent
            folder
        }
        var bookmarkList: BookmarkList?
        let e = expectation(description: "list published")
        let cancellable = bookmarkManager.listPublisher
            .dropFirst()
            .sink { list in
                bookmarkList = list
                e.fulfill()
            }

        bookmarkManager.update(folder: folder, andMoveToParent: .parent(uuid: parent.id))

        await fulfillment(of: [e], timeout: 5)
        cancellable.cancel()

        XCTAssertTrue(bookmarkStoreMock.updateFolderAndMoveToParentCalled)
        XCTAssertEqual(bookmarkStoreMock.capturedFolder, folder)
        XCTAssertEqual(bookmarkStoreMock.capturedParentFolderType, .parent(uuid: parent.id))
        XCTAssertNotNil(bookmarkList)
    }

    @MainActor
    func testWhenGetBookmarkFolderIsCalledThenAskBookmarkStoreToRetrieveFolder() async throws {
        // GIVEN
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        XCTAssertFalse(bookmarkStoreMock.bookmarkFolderWithIdCalled)
        XCTAssertNil(bookmarkStoreMock.capturedFolderId)

        // WHEN
        _ = bookmarkManager.getBookmarkFolder(withId: #function)

        // THEN
        XCTAssertTrue(bookmarkStoreMock.bookmarkFolderWithIdCalled)
        XCTAssertEqual(bookmarkStoreMock.capturedFolderId, #function)
    }

    @MainActor
    func testWhenGetBookmarkFolderIsCalledAndFolderExistsInStoreThenBookmarkStoreReturnsFolder() async throws {
        // GIVEN
        let folder = BookmarkFolder(id: #function, title: "Test")
        let (bookmarkManager, _) = await manager { folder }

        // WHEN
        let result = bookmarkManager.getBookmarkFolder(withId: #function)

        // THEN
        XCTAssertEqual(result, folder)
    }

    @MainActor
    func testWhenGetBookmarkFolderIsCalledAndFolderDoesNotExistInStoreThenBookmarkStoreReturnsNil() async throws {
        // GIVEN
        let (bookmarkManager, _) = await aManager()

        // WHEN
        let result = bookmarkManager.getBookmarkFolder(withId: #function)

        // THEN
        XCTAssertNil(result)
    }

    // MARK: - Folders Store

    @MainActor
    func testThatLastUsedFolderIsNilByDefault() async {
        let (_, _) = await aManager()
        XCTAssertEqual(foldersStore.lastBookmarkSingleTabFolderIdUsed, nil)
    }

    @MainActor
    func testWhenBookmarkIsAdded_ThenLastUsedFolderIsUpdated() async throws {
        let (bookmarkManager, _) = await aManager()
        let folder = try await bookmarkManager.makeFolder(named: "sample folder")

        await withCheckedContinuation { continuation in
            bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false, parent: folder) { _ in
                continuation.resume()
            }
        }

        XCTAssertEqual(foldersStore.lastBookmarkSingleTabFolderIdUsed, folder.id)
    }

    @MainActor
    func testWhenBookmarkIsMoved_ThenLastUsedFolderIsUpdatedWithNewParentFolder() async throws {
        let (bookmarkManager, _) = await aManager()
        let folder1 = try await bookmarkManager.makeFolder(named: "sample folder")
        let folder2 = try await bookmarkManager.makeFolder(named: "other sample folder")
        var bookmark: Bookmark?

        await withCheckedContinuation { continuation in
            bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false, parent: folder1) { _ in
                continuation.resume()
            }
        }

        let id = try XCTUnwrap(bookmark?.id)
        await withCheckedContinuation { continuation in
            bookmarkManager.move(objectUUIDs: [id], toIndex: nil, withinParentFolder: .parent(uuid: folder2.id)) { _ in
                continuation.resume()
            }
        }

        XCTAssertEqual(foldersStore.lastBookmarkSingleTabFolderIdUsed, folder2.id)
    }

    @MainActor
    func testWhenBookmarkIsMovedUsingAddObjectsWithUUIDs_ThenLastUsedFolderIsUpdatedWithNewParentFolder() async throws {
        let (bookmarkManager, _) = await aManager()
        let folder1 = try await bookmarkManager.makeFolder(named: "sample folder")
        let folder2 = try await bookmarkManager.makeFolder(named: "other sample folder")
        var bookmark: Bookmark?

        await withCheckedContinuation { continuation in
            bookmark = bookmarkManager.makeBookmark(for: URL.duckDuckGo, title: "Title", isFavorite: false, parent: folder1) { _ in
                continuation.resume()
            }
        }

        let id = try XCTUnwrap(bookmark?.id)
        await withCheckedContinuation { continuation in
            bookmarkManager.add(objectsWithUUIDs: [id], to: folder2) { _ in
                continuation.resume()
            }
        }

        XCTAssertEqual(foldersStore.lastBookmarkSingleTabFolderIdUsed, folder2.id)
    }

    @MainActor
    func testWhenFolderIsMoved_ThenLastUsedFolderIsUpdatedWithNewParentFolder() async throws {
        let (bookmarkManager, _) = await aManager()
        let folder1 = try await bookmarkManager.makeFolder(named: "sample folder")
        let folder2 = try await bookmarkManager.makeFolder(named: "other sample folder")

        await withCheckedContinuation { continuation in
            bookmarkManager.move(objectUUIDs: [folder2.id], toIndex: nil, withinParentFolder: .parent(uuid: folder1.id)) { _ in
                continuation.resume()
            }
        }

        XCTAssertEqual(foldersStore.lastBookmarkSingleTabFolderIdUsed, folder1.id)
    }

    // MARK: - Save Multiple Bookmarks at once

    @MainActor
    func testWhenMakeBookmarksForWebsitesInfoIsCalledThenBookmarkStoreIsAskedToCreateMultipleBookmarks() async {
        // GIVEN
        let (sut, bookmarkStoreMock) = await aManager()
        let newFolderName = #function
        let websitesInfo = [
            WebsiteInfo(url: URL.duckDuckGo, title: "Website 1"),
            WebsiteInfo(url: URL.duckDuckGo, title: "Website 2"),
            WebsiteInfo(url: URL.duckDuckGo, title: "Website 3"),
            WebsiteInfo(url: URL.duckDuckGo, title: "Website 4"),
        ].compactMap { $0 }
        XCTAssertFalse(bookmarkStoreMock.saveBookmarksInNewFolderNamedCalled)
        XCTAssertNil(bookmarkStoreMock.capturedWebsitesInfo)
        XCTAssertNil(bookmarkStoreMock.capturedNewFolderName)
        XCTAssertNil(bookmarkStoreMock.capturedParentFolderType)

        // WHEN
        sut.makeBookmarks(for: websitesInfo, inNewFolderNamed: newFolderName, withinParentFolder: .root)

        // THEN
        XCTAssertTrue(bookmarkStoreMock.saveBookmarksInNewFolderNamedCalled)
        XCTAssertEqual(bookmarkStoreMock.capturedWebsitesInfo?.count, 4)
        XCTAssertEqual(bookmarkStoreMock.capturedWebsitesInfo, websitesInfo)
        XCTAssertEqual(bookmarkStoreMock.capturedNewFolderName, newFolderName)
        XCTAssertEqual(bookmarkStoreMock.capturedParentFolderType, .root)
    }

    @MainActor
    func testWhenMakeBookmarksForWebsiteInfoIsCalledThenReloadAllBookmarks() async {
        // GIVEN
        let (sut, bookmarkStoreMock) = await aManager()
        bookmarkStoreMock.loadAllCalled = false // Reset after load all bookmarks the first time
        XCTAssertFalse(bookmarkStoreMock.loadAllCalled)
        let websitesInfo = [WebsiteInfo(url: URL.duckDuckGo, title: "Website 1")].compactMap { $0 }

        // WHEN
        sut.makeBookmarks(for: websitesInfo, inNewFolderNamed: "Test", withinParentFolder: .root)

        // THEN
        XCTAssertTrue(bookmarkStoreMock.loadAllCalled)
    }

    // MARK: - Search

    func testWhenBookmarkListIsNilThenSearchIsEmpty() {
        let sut = LocalBookmarkManager(bookmarkStore: BookmarkStoreMock(), appearancePreferences: .mock)
        let results = sut.search(by: "abc")

        XCTAssertNil(sut.list)
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testWhenQueryIsEmptyThenSearchResultsAreEmpty() async {
        let (sut, _) = await manager(with: topLevelBookmarks)
        let results = sut.search(by: "")

        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testWhenQueryIsBlankThenSearchResultsAreEmpty() async {
        let (sut, _) = await manager(with: topLevelBookmarks)

        let results = sut.search(by: "    ")

        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testWhenASearchIsDoneThenCorrectResultsAreReturnedAndIntheRightOrder() async {
        let (sut, _) = await manager(with: topLevelBookmarks)
        let results = sut.search(by: "folder")

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[safe: 0]?.title, "This is a folder")
        XCTAssertEqual(results[safe: 1]?.title, "Favorite folder")
        XCTAssertEqual(results[safe: 2]?.title, "This is a sub-folder")
    }

    @MainActor
    func testWhenASearchIsDoneThenFoldersAndBookmarksAreReturned() async {
        let (sut, _) = await manager(with: topLevelBookmarks)
        let results = sut.search(by: "favorite")

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[safe: 0]?.title, "Favorite folder")
        XCTAssert(results[safe: 0]?.isFolder == true)
        XCTAssertEqual(results[safe: 1]?.title, "Favorite bookmark")
        XCTAssert(results[safe: 1]?.isFolder == false)
    }

    @MainActor
    func testWhenASearchIsDoneThenItMatchesWithLowercaseResults() async {
        let (sut, _) = await manager {
            Bookmark(id: "1", url: "www.favorite.com", title: "Favorite bookmark", isFavorite: true)
            Bookmark(id: "2", url: "www.favoritetwo.com", title: "favorite bookmark", isFavorite: true)
        }

        let resultsWhtCapitalizedQuery = sut.search(by: "Favorite")
        let resultsWithNotCapitalizedQuery = sut.search(by: "favorite")

        XCTAssertTrue(resultsWhtCapitalizedQuery.count == 2)
        XCTAssertTrue(resultsWithNotCapitalizedQuery.count == 2)
    }

    @MainActor
    func testSearchIgnoresAccents() async {
        let (sut, _) = await manager {
            Bookmark(id: "1", url: "www.coffee.com", title: "Mi café favorito", isFavorite: true)
            Bookmark(id: "1", url: "www.coffee.com", title: "Mi cafe favorito", isFavorite: true)
        }

        let resultsWithoutAccent = sut.search(by: "cafe")
        let resultsWithAccent = sut.search(by: "café")

        XCTAssertTrue(resultsWithoutAccent.count == 2)
        XCTAssertTrue(resultsWithAccent.count == 2)
    }

    @MainActor
    func testWhenASearchIsDoneWithoutAccenttsThenItMatchesBookmarksWithoutAccent() async {
        let (sut, _) = await manager {
            Bookmark(id: "1", url: "www.coffee.com", title: "Mi café favorito", isFavorite: true)
        }

        let results = sut.search(by: "cafe")

        XCTAssertTrue(results.count == 1)
    }

    @MainActor
    func testWhenBookmarkHasASymbolThenItsIgnoredWhenSearching() async {
        let (sut, _) = await manager {
            Bookmark(id: "1", url: "www.test.com", title: "Site • Login", isFavorite: true)
        }

        let results = sut.search(by: "site login")

        XCTAssertTrue(results.count == 1)
    }

    @MainActor
    func testSearchQueryHasASymbolThenItsIgnoredWhenSearching() async {
        let (sut, _) = await manager {
            Bookmark(id: "1", url: "www.test.com", title: "Site Login", isFavorite: true)
        }

        let results = sut.search(by: "site • login")

        XCTAssertTrue(results.count == 1)
    }

    @BookmarksBuilder
    private func topLevelBookmarks() -> [BookmarksBuilderItem] {
        folder(id: "2", "This is a folder") {
            folder(id: "1", "This is a sub-folder") {
                Bookmark(id: "3", url: "www.ddg.com", title: "This is a bookmark", isFavorite: false)
            }
        }
        folder(id: "5", "Favorite folder") {
            Bookmark(id: "4", url: "www.favorite.com", title: "Favorite bookmark", isFavorite: true)
        }
    }

    func testWhenVariantUrlIsBookmarked_ThenGetBookmarkForVariantReturnsBookmark() async throws {
        let originalURL = URL(string: "http://example.com")!
        let variantURL = URL(string: "https://example.com/")!
        let bookmark = Bookmark(id: UUID().uuidString, url: variantURL.absoluteString, title: "Title", isFavorite: false, parentFolderUUID: "bookmarks_root")
        let (bookmarkManager, bookmarkStoreMock) = await manager(with: {
            bookmark
        })
        bookmarkManager.loadBookmarks()

        let result = bookmarkManager.getBookmark(forVariantUrl: originalURL)

        XCTAssertEqual(result, bookmark)
        XCTAssert(bookmarkStoreMock.loadAllCalled)
    }

    @MainActor
    func testWhenNoVariantUrlIsBookmarked_ThenGetBookmarkForVariantReturnsNil() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let originalURL = URL(string: "http://example.com")!

        bookmarkStoreMock.bookmarks = []
        bookmarkManager.loadBookmarks()

        let result = bookmarkManager.getBookmark(forVariantUrl: originalURL)

        XCTAssertNil(result)
    }

    func testWhenVariantUrlIsBookmarked_ThenIsAnyUrlVariantBookmarkedReturnsTrue() async throws {
        let originalURL = URL(string: "http://example.com")!
        let variantURL = URL(string: "https://example.com/")!
        let bookmark = Bookmark(id: UUID().uuidString, url: variantURL.absoluteString, title: "Title", isFavorite: false, parentFolderUUID: "bookmarks_root")
        let (bookmarkManager, _) = await manager(with: {
            bookmark
        })
        bookmarkManager.loadBookmarks()

        let result = bookmarkManager.isAnyUrlVariantBookmarked(url: originalURL)

        XCTAssertTrue(result)
    }

    @MainActor
    func testWhenNoVariantUrlIsBookmarked_ThenIsAnyUrlVariantBookmarkedReturnsFalse() async {
        let (bookmarkManager, bookmarkStoreMock) = await aManager()
        let originalURL = URL(string: "http://example.com")!

        bookmarkStoreMock.bookmarks = []
        bookmarkManager.loadBookmarks()

        let result = bookmarkManager.isAnyUrlVariantBookmarked(url: originalURL)

        XCTAssertFalse(result)
    }

}

fileprivate extension LocalBookmarkManagerTests {

    @MainActor
    func aManager() async -> (LocalBookmarkManager, BookmarkStoreMock) {
        await manager(with: {})
    }

    @MainActor
    private func makeManager(@BookmarksBuilder with bookmarks: () -> [BookmarksBuilderItem]) -> (LocalBookmarkManager, BookmarkStoreMock) {
        let bookmarkStoreMock = BookmarkStoreMock(contextProvider: context.map { context in { context } }, bookmarks: bookmarks().build())
        foldersStore = BookmarkFolderStoreMock()
        let bookmarkManager = LocalBookmarkManager(bookmarkStore: bookmarkStoreMock, foldersStore: foldersStore, appearancePreferences: .mock)
        Logger.tests.debug("LocalBookmarkManagerTests.\(self.name).makeManager \(String(describing: bookmarkManager)) with \(bookmarkStoreMock.debugDescription, privacy: .public)")

        return (bookmarkManager, bookmarkStoreMock)
    }

    @MainActor
    func manager(loadBookmarks: Bool = true, @BookmarksBuilder with bookmarks: () -> [BookmarksBuilderItem]) async -> (LocalBookmarkManager, BookmarkStoreMock) {
        let (bookmarkManager, bookmarkStoreMock) = makeManager(with: bookmarks)
        if loadBookmarks {
            bookmarkManager.loadBookmarks()
            while bookmarkManager.list == nil {
                try? await Task.sleep(interval: 0.001)
            }
        }
        return (bookmarkManager, bookmarkStoreMock)
    }
}

fileprivate extension BookmarkManager {

    @MainActor
    func makeFolder(named name: String, parent: BookmarkFolder? = nil) async throws -> BookmarkFolder {
        try await withCheckedThrowingContinuation { continuation in
            makeFolder(named: "sample folder", parent: parent) { result in
                switch result {
                case .success(let folder):
                    continuation.resume(returning: folder)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

fileprivate extension Bookmark {

    static var aBookmark: Bookmark = Bookmark(id: UUID().uuidString,
                                              url: URL.duckDuckGo.absoluteString,
                                              title: "Title",
                                              isFavorite: false)
    convenience init(_ url: URL, isFavorite: Bool = false, parentId: String? = nil) {
        self.init(id: UUID().uuidString, url: url.absoluteString, title: url.absoluteString.dropping(prefix: url.navigationalScheme?.separated() ?? ""), isFavorite: isFavorite, parentFolderUUID: parentId)
    }
}
fileprivate extension BookmarkFolder {
    convenience init(_ title: String) {
        self.init(id: UUID().uuidString, title: title)
    }
}

fileprivate extension BaseBookmarkEntity {

    func matchesBookmark(withTitle title: String, url: URL, isFavorite: Bool, parent: String? = nil) -> Bool {
        guard let bookmark = self as? Bookmark else { return false }
        let lhsIsInRoot = bookmark.parentFolderUUID == nil || bookmark.parentFolderUUID == "bookmarks_root" || bookmark.parentFolderUUID == PseudoFolder.bookmarks.id
        let rhsIsInRoot = parent == nil || parent == "bookmarks_root" || parent == PseudoFolder.bookmarks.id
        return bookmark.title == title && bookmark.url == url.absoluteString && bookmark.isFavorite == isFavorite && lhsIsInRoot == rhsIsInRoot
    }

    func matchesBookmark(withTitle title: String, url: URL, isFavorite: Bool, parent: BookmarkFolder? = nil) -> Bool {
        matchesBookmark(withTitle: title, url: url, isFavorite: isFavorite, parent: parent?.id)
    }

    func matches(_ entity: BaseBookmarkEntity?) -> Bool {
        switch entity {
        case let bookmark as Bookmark:
            return matchesBookmark(withTitle: bookmark.title, url: URL(string: bookmark.url)!, isFavorite: bookmark.isFavorite, parent: bookmark.parentFolderUUID)
        case let folder as BookmarkFolder:
            return matchesFolder(withTitle: folder.title, parent: folder.parentFolderUUID)
        case .none:
            return false
        case .some(let entity):
            fatalError("Unexpected entity type \(entity)")
        }
    }

    func matchesFolder(withTitle title: String, parent: String?) -> Bool {
        guard self.isFolder else { return false }
        return self.title == title && self.parentFolderUUID ?? "bookmarks_root" == parent ?? "bookmarks_root"
    }

    func matches(_ folder: BookmarkFolder) -> Bool {
        matchesFolder(withTitle: folder.title, parent: folder.parentFolderUUID)
    }

}

protocol BookmarksBuilderItem {
    func build(withParentId parentId: String?) -> BaseBookmarkEntity
}
extension BookmarksBuilderItem {
    func build() -> BaseBookmarkEntity {
        build(withParentId: nil)
    }
}
extension BaseBookmarkEntity: BookmarksBuilderItem {
    func build(withParentId parentId: String?) -> BaseBookmarkEntity {
        switch self {
        case let bookmark as Bookmark:
            Bookmark(id: bookmark.id, url: bookmark.url, title: bookmark.title, isFavorite: bookmark.isFavorite, parentFolderUUID: bookmark.parentFolderUUID, faviconManagement: bookmark.faviconManagement)
        case let folder as BookmarkFolder:
            BookmarkFolder(id: folder.id, title: folder.title, parentFolderUUID: folder.parentFolderUUID, children: folder.children)
        default:
            fatalError("Unexpected entity type \(self)")
        }
    }
}
private typealias BookmarksBuilder = ArrayBuilder<BookmarksBuilderItem>
private indirect enum BookmarksBuilderItemMock: BookmarksBuilderItem {
    case bookmark(id: String = UUID().uuidString, title: String, url: URL, isFavorite: Bool = false)
    case folder(id: String = UUID().uuidString, title: String, items: [BookmarksBuilderItem])

    func build(withParentId parentId: String? = nil) -> BaseBookmarkEntity {
        switch self {
        case let .bookmark(id: id, title: title, url: url, isFavorite: isFavorite):
            Bookmark(id: id, url: url.absoluteString, title: title, isFavorite: isFavorite, parentFolderUUID: parentId)
        case let .folder(id: id, title: title, items: items):
            BookmarkFolder(id: id, title: title, parentFolderUUID: parentId, children: items.build(withParentId: id))
        }
    }
}
private extension LocalBookmarkManagerTests {
    func bookmark(_ id: String, _ url: URL, isFavorite: Bool = false) -> BookmarksBuilderItem {
        return BookmarksBuilderItemMock.bookmark(id: id, title: url.absoluteString.dropping(prefix: url.navigationalScheme?.separated() ?? ""), url: url, isFavorite: isFavorite)
    }
    func bookmark(_ url: URL, isFavorite: Bool = false) -> BookmarksBuilderItem {
        return BookmarksBuilderItemMock.bookmark(title: url.absoluteString.dropping(prefix: url.navigationalScheme?.separated() ?? ""), url: url, isFavorite: isFavorite)
    }
    func folder(id: String = UUID().uuidString, _ title: String, @BookmarksBuilder items: () -> [BookmarksBuilderItem]) -> BookmarksBuilderItem {
        BookmarksBuilderItemMock.folder(id: id, title: title, items: items())
    }
    func folder(id: String = UUID().uuidString, _ title: String) -> BookmarksBuilderItem {
        BookmarksBuilderItemMock.folder(id: id, title: title, items: [])
    }
    func assertEqual(_ lhs: [(entity: BaseBookmarkEntity, index: Int?, indexInFavoritesArray: Int?)]?, _ rhs: [(entity: BaseBookmarkEntity, index: Int?, indexInFavoritesArray: Int?)]?, file: StaticString = #file, line: UInt = #line) {
        if lhs == nil, rhs == nil { return }
        var overviewPrinted = false
        func fail(_ message: String) {
            if !overviewPrinted {
                overviewPrinted = true
                XCTFail("\(lhs.map { "\($0)" } ?? "<nil>")\n  is not equal to\n\(rhs?.map { "\($0)" }.joined(separator: ",\n") ?? "<nil>")", file: file, line: line)
            }
            XCTFail(message, file: file, line: line)
        }
        guard let lhs else { return fail("<nil> is not equal to \(rhs!)") }
        guard let rhs else { return fail("\(lhs) is not equal to <nil>") }
        for idx in 0..<max(lhs.endIndex, rhs.endIndex) {
            guard let lhsItem = lhs[safe: idx] else {
                fail("#\(idx): <nil> is not equal to \(rhs[idx])")
                continue
            }
            guard let rhsItem = rhs[safe: idx] else {
                fail("#\(idx): \(lhsItem) is not equal to <nil>")
                continue
            }
            switch (lhsItem.entity.matches(rhsItem.entity), lhsItem.index == rhsItem.index) {
            case (true, true): continue
            case (true, false): fail("#\(idx): index \(lhsItem.index.map(String.init) ?? "<nil>") ≠ \(rhsItem.index.map(String.init) ?? "<nil>")")
            case (false, true): fail("#\(idx): \(lhsItem.entity) ≠ \(rhsItem.entity)")
            case (false, false): fail("#\(idx): \(lhsItem.entity) at \(lhsItem.index.map(String.init) ?? "<nil>") ≠ \(rhsItem.entity) at \(rhsItem.index.map(String.init) ?? "<nil>")")
            }
        }
    }
}

extension [BookmarksBuilderItem] {
    func build(withParentId parentId: String? = nil) -> [BaseBookmarkEntity] {
        self.map { $0.build(withParentId: parentId) }
    }
}

private extension WebsiteInfo {

    @MainActor
    init?(url: URL, title: String) {
        let tab = Tab(content: .url(url, credential: nil, source: .ui))
        tab.title = title
        self.init(tab)
    }

}
