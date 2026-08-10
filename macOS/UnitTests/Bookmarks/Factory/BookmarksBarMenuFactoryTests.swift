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
        XCTAssertEqual(menu.items.count, 5)
        XCTAssertEqual(menu.items[1].title, "")
        XCTAssertNil(menu.items[1].action)
        XCTAssertEqual(menu.items[2].title, UserText.addFolder)
        XCTAssertEqual(menu.items[2].action, #selector(targetMock.addFolder(_:)))
        XCTAssertEqual(menu.items[3].title, UserText.bookmarksBarContextMenuReorderByName)
        XCTAssertEqual(menu.items[3].action, #selector(targetMock.reorderByName(_:)))
        XCTAssertEqual(menu.items[3].image?.pngData(), DesignSystemImages.Glyphs.Size12.arrowUpDown.pngData())
        XCTAssertEqual(menu.items[4].title, UserText.bookmarksManageBookmarks)
        XCTAssertEqual(menu.items[4].action, #selector(targetMock.manageBookmarks))
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
    }

    func testReorderByNameMovesTopLevelEntitiesWithinRoot() {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        let bookmarkManager = MockBookmarkManager(
            list: BookmarkList(entities: [zulu], topLevelEntities: [zulu, alpha]),
            sortMode: .nameDescending)

        // WHEN
        bookmarkManager.reorderByName(bookmarkManager.list?.topLevelEntities ?? [], withinParentFolder: .root)

        // THEN
        XCTAssertEqual(
            bookmarkManager.moveObjectsCalled,
            .init(objectUUIDs: [alpha.id, zulu.id], toIndex: 0, withinParentFolder: .root))
        XCTAssertEqual(bookmarkManager.sortMode, .manual)
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
