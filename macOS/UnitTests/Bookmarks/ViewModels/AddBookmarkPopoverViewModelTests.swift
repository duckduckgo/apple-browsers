//
//  AddBookmarkPopoverViewModelTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo_Privacy_Browser

final class AddBookmarkPopoverViewModelTests: XCTestCase {

    var viewModel: AddBookmarkPopoverViewModel!
    var bookmarkManager: LocalBookmarkManager!
    var bookmarkStoreMock: BookmarkStoreMock!
    var foldersStore: BookmarkFolderStoreMock!
    var buttonClickedCallsCount: Int = 0

    @MainActor
    override func setUp() async throws {
        let bookmark = Bookmark.mock
        bookmarkStoreMock = BookmarkStoreMock(bookmarks: [bookmark])
        bookmarkManager = .init(bookmarkStore: bookmarkStoreMock, appearancePreferences: .mock)
        bookmarkManager.loadBookmarks()
        buttonClickedCallsCount = 0

        viewModel = AddBookmarkPopoverViewModel(bookmark: bookmark, bookmarkManager: bookmarkManager)
        viewModel.buttonClicked = {
            self.buttonClickedCallsCount += 1
        }
    }

    override func tearDown() {
        viewModel = nil
        bookmarkManager = nil
        bookmarkStoreMock = nil
        foldersStore = nil
    }

    @MainActor
    func testWhenBookmarkFavoriteStateIsUpdatedThenBookmarkIsUpdated() throws {
        viewModel.isBookmarkFavorite = true
        XCTAssertEqual(viewModel.bookmark.isFavorite, true)
        viewModel.isBookmarkFavorite = false
        XCTAssertEqual(viewModel.bookmark.isFavorite, false)
    }

    @MainActor
    func testWhenBookmarkTitleIsUpdatedThenBookmarkIsUpdated() throws {
        viewModel.bookmarkTitle = "abcd"
        XCTAssertEqual(viewModel.bookmark.title, "abcd")
        viewModel.bookmarkTitle = "Sample bookmark"
        XCTAssertEqual(viewModel.bookmark.title, "Sample bookmark")
    }

    @MainActor
    func testThatRemoveButtonActionRemovesBookmarkAndTriggersButtonClickedCallback() throws {
        let url = try XCTUnwrap(viewModel.bookmark.urlObject)
        XCTAssertTrue(bookmarkManager.isUrlBookmarked(url: url))

        viewModel.removeButtonAction()

        XCTAssertFalse(bookmarkManager.isUrlBookmarked(url: url))
        XCTAssertEqual(buttonClickedCallsCount, 1)
    }

    @MainActor
    func testThatDoneButtonActionTriggersButtonClickedCallback() throws {
        viewModel.doneButtonAction()
        XCTAssertEqual(buttonClickedCallsCount, 1)
    }
}
