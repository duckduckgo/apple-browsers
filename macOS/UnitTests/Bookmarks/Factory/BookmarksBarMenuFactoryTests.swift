//
//  BookmarksBarMenuFactoryTests.swift
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

import DesignResourcesKitIcons
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class BookmarksBarMenuFactoryTests: XCTestCase {

    func testReturnAddFolderAndManageBookmarksWhenAddToMenuWithManageBookmarksSectionIsCalled() {
        // GIVEN
        let menu = NSMenu(title: "")
        let targetMock = BookmarksBarTargetMock()
        XCTAssertTrue(menu.items.isEmpty)

        // WHEN
        BookmarksBarMenuFactory.addToMenuWithManageBookmarksSection(
            menu,
            target: targetMock,
            addFolderSelector: #selector(targetMock.addFolder(_:)),
            reorderByNameSelector: #selector(targetMock.reorderByName(_:)),
            manageBookmarksSelector: #selector(targetMock.manageBookmarks),
            prefs: NSApp.delegateTyped.appearancePreferences)

        // THEN
        XCTAssertEqual(menu.items.count, 6)
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, UserText.bookmarksBarContextMenuReorderByName)
        XCTAssertEqual(menu.items[2].action, #selector(targetMock.reorderByName(_:)))
        XCTAssertEqual(menu.items[2].image?.pngData(), DesignSystemImages.Glyphs.Size12.arrowUpDown.pngData())
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, UserText.addFolder)
        XCTAssertEqual(menu.items[4].action, #selector(targetMock.addFolder(_:)))
        XCTAssertEqual(menu.items[5].title, UserText.bookmarksManageBookmarks)
        XCTAssertEqual(menu.items[5].action, #selector(targetMock.manageBookmarks))
    }

    func testReorderByNameIsMissingWhenSelectorIsNil() {
        // GIVEN
        let menu = NSMenu(title: "")
        let targetMock = BookmarksBarTargetMock()

        // WHEN
        BookmarksBarMenuFactory.addToMenuWithManageBookmarksSection(
            menu,
            target: targetMock,
            addFolderSelector: #selector(targetMock.addFolder(_:)),
            reorderByNameSelector: nil,
            manageBookmarksSelector: #selector(targetMock.manageBookmarks),
            prefs: NSApp.delegateTyped.appearancePreferences)

        // THEN
        XCTAssertEqual(menu.items.count, 4)
        XCTAssertFalse(menu.items.contains(where: { $0.title == UserText.bookmarksBarContextMenuReorderByName }))
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertEqual(menu.items[2].title, UserText.addFolder)
        XCTAssertEqual(menu.items[3].title, UserText.bookmarksManageBookmarks)
    }

    @MainActor
    func testReorderByNameMovesTopLevelEntitiesWithinRoot() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)

        // WHEN
        bookmarkManager.reorderByName(
            [zulu, alpha],
            withinParentFolder: .root,
            undoManager: nil)

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls.last,
            .init(objectUUIDs: [alpha.id, zulu.id], toIndex: 0, withinParentFolder: .root))
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
    }

    @MainActor
    func testWhenReorderByNameIsUndoneAndRedoneThenExactOrderAndSortModeAreRestored() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        let undoManager = UndoManager()

        // WHEN
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls,
            [.init(objectUUIDs: [alpha.id, zulu.id], toIndex: 0, withinParentFolder: .root)])
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, UserText.bookmarksUndoActionReorderByName)

        // WHEN
        undoManager.undo()

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls.last,
            .init(objectUUIDs: [zulu.id, alpha.id], toIndex: 0, withinParentFolder: .root))
        XCTAssertEqual(bookmarkManager.sortMode, .nameDescending)
        XCTAssertTrue(undoManager.canRedo)

        // WHEN
        undoManager.redo()

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls.last,
            .init(objectUUIDs: [alpha.id, zulu.id], toIndex: 0, withinParentFolder: .root))
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
        XCTAssertTrue(undoManager.canUndo)
    }

    @MainActor
    func testWhenUndoArrivesBeforeReorderPersistenceCompletesThenMovesAreSerialized() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        bookmarkStore.defersMoveCompletions = true
        let undoManager = UndoManager()

        // WHEN
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)
        undoManager.undo()

        // THEN
        XCTAssertEqual(bookmarkStore.moveObjectsCalls.count, 1)
        XCTAssertEqual(bookmarkStore.deferredMoveCompletionCount, 1)

        // WHEN
        bookmarkStore.completeNextMove()

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls,
            [
                .init(objectUUIDs: [alpha.id, zulu.id], toIndex: 0, withinParentFolder: .root),
                .init(objectUUIDs: [zulu.id, alpha.id], toIndex: 0, withinParentFolder: .root),
            ])
        XCTAssertEqual(bookmarkStore.deferredMoveCompletionCount, 1)

        // WHEN
        bookmarkStore.completeNextMove()

        // THEN
        XCTAssertEqual(bookmarkManager.sortMode, .nameDescending)
        XCTAssertTrue(undoManager.canRedo)
    }

    @MainActor
    func testWhenUndoAndRedoArriveBeforePersistenceCompletesThenLatestStateIsApplied() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        bookmarkStore.defersMoveCompletions = true
        let undoManager = UndoManager()

        // WHEN
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)
        undoManager.undo()
        undoManager.redo()

        // THEN
        XCTAssertEqual(bookmarkStore.moveObjectsCalls.count, 1)
        XCTAssertEqual(bookmarkStore.deferredMoveCompletionCount, 1)

        // WHEN
        bookmarkStore.completeNextMove()
        bookmarkStore.completeNextMove()

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls.map(\.objectUUIDs),
            [
                [alpha.id, zulu.id],
                [alpha.id, zulu.id],
            ])
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertFalse(undoManager.canRedo)
    }

    @MainActor
    func testWhenSortModeChangesWhileReorderIsPendingThenCompletionDoesNotOverwriteIt() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        bookmarkStore.defersMoveCompletions = true

        // WHEN
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: nil)
        bookmarkManager.sortMode = .nameAscending
        bookmarkStore.completeNextMove()

        // THEN
        XCTAssertEqual(bookmarkManager.sortMode, .nameAscending)
    }

    @MainActor
    func testWhenSortModeChangesAfterReorderThenUndoRestoresOrderWithoutOverwritingNewMode() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        let undoManager = UndoManager()
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)

        // WHEN
        bookmarkManager.sortMode = .nameAscending
        undoManager.undo()

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls.last,
            .init(objectUUIDs: [zulu.id, alpha.id], toIndex: 0, withinParentFolder: .root))
        XCTAssertEqual(bookmarkManager.sortMode, .nameAscending)
    }

    @MainActor
    func testWhenInitialReorderFailsThenRedoRetriesTheReorder() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        bookmarkStore.defersMoveCompletions = true
        bookmarkStore.moveObjectsError = NSError(domain: "BookmarksBarMenuFactoryTests", code: 1)
        let undoManager = UndoManager()

        // WHEN
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)
        bookmarkStore.completeNextMove()

        // THEN
        XCTAssertEqual(bookmarkManager.sortMode, .nameDescending)
        XCTAssertTrue(undoManager.canUndo)

        // WHEN
        bookmarkStore.moveObjectsError = nil
        undoManager.undo()
        bookmarkStore.completeNextMove()
        undoManager.redo()
        bookmarkStore.completeNextMove()

        // THEN
        XCTAssertEqual(
            bookmarkStore.moveObjectsCalls.map(\.objectUUIDs),
            [
                [alpha.id, zulu.id],
                [zulu.id, alpha.id],
                [alpha.id, zulu.id],
            ])
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
    }

    @MainActor
    func testWhenOrderIsAlreadyAlphabeticalAndModeChangesThenOnlyModeIsUndoable() {
        // GIVEN
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        let undoManager = UndoManager()

        // WHEN
        bookmarkManager.reorderByName([alpha, zulu], withinParentFolder: .root, undoManager: undoManager)

        // THEN
        XCTAssertTrue(bookmarkStore.moveObjectsCalls.isEmpty)
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
        XCTAssertTrue(undoManager.canUndo)

        // WHEN
        undoManager.undo()

        // THEN
        XCTAssertEqual(bookmarkManager.sortMode, .nameDescending)
        XCTAssertTrue(undoManager.canRedo)

        // WHEN
        undoManager.redo()

        // THEN
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
    }

    @MainActor
    func testWhenOrderIsAlreadyAlphabeticalAndModeIsManualThenReorderIsNoOp() {
        // GIVEN
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let (bookmarkManager, bookmarkStore) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .manual)
        let undoManager = UndoManager()

        // WHEN
        bookmarkManager.reorderByName([alpha, zulu], withinParentFolder: .root, undoManager: undoManager)

        // THEN
        XCTAssertTrue(bookmarkStore.moveObjectsCalls.isEmpty)
        XCTAssertFalse(undoManager.canUndo)
    }

    @MainActor
    func testWhenDeleteFollowsReorderThenDeleteIsTheNextUndoAction() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, _) = ReorderBookmarkManagerTestFactory.makeManager(
            sortMode: .nameDescending,
            bookmarks: [zulu, alpha])
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        // WHEN
        undoManager.beginUndoGrouping()
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
        bookmarkManager.remove(bookmark: zulu, undoManager: undoManager)
        undoManager.endUndoGrouping()

        // THEN
        XCTAssertEqual(undoManager.undoActionName, UserText.deleteBookmark)

        // WHEN
        undoManager.undo()

        // THEN
        XCTAssertEqual(undoManager.undoActionName, UserText.bookmarksUndoActionReorderByName)
    }

    @MainActor
    func testWhenActionsForBookmarkManagerAreRemovedThenReorderUndoIsCleared() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, _) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)
        undoManager.endUndoGrouping()
        XCTAssertTrue(undoManager.canUndo)

        // WHEN
        undoManager.removeAllActions(withTarget: bookmarkManager)

        // THEN
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertFalse(undoManager.canRedo)
    }

    @MainActor
    func testWhenUndoManagerOwnerIsReleasedThenReorderHandlerDoesNotRetainUndoManager() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let (bookmarkManager, _) = ReorderBookmarkManagerTestFactory.makeManager(sortMode: .nameDescending)
        weak var weakUndoManager: UndoManager?

        // WHEN
        do {
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            undoManager.beginUndoGrouping()
            weakUndoManager = undoManager
            bookmarkManager.reorderByName([zulu, alpha], withinParentFolder: .root, undoManager: undoManager)
            undoManager.endUndoGrouping()
        }

        // THEN
        XCTAssertNil(weakUndoManager)
    }

    func testShouldNotReturnAddFolderAndManageBookmarksWhenAddToMenuIsCalled() {
        // GIVEN
        let menu = NSMenu(title: "")
        XCTAssertTrue(menu.items.isEmpty)

        // WHEN
        BookmarksBarMenuFactory.addToMenu(menu, prefs: NSApp.delegateTyped.appearancePreferences)

        // THEN
        XCTAssertEqual(menu.items.count, 1)
    }

}

private class BookmarksBarTargetMock: NSObject {
    @objc func addFolder(_ sender: NSMenuItem) {}
    @objc func reorderByName(_ sender: NSMenuItem) {}
    @objc func manageBookmarks() {}
}
