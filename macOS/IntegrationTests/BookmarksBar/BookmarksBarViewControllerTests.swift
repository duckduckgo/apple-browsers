//
//  BookmarksBarViewControllerTests.swift
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
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class BookmarksBarViewControllerTests: XCTestCase {

    var vc: BookmarksBarViewController!
    var bookmarksManager: MockBookmarkManager!
    var cancellables: Set<AnyCancellable> = []

    @MainActor override func setUpWithError() throws {
        bookmarksManager = MockBookmarkManager()
    }

    override func tearDownWithError() throws {
        vc = nil
        bookmarksManager = nil
        cancellables.removeAll()
    }

    @MainActor
    func testWhenImportBookmarksClicked_ThenDataImportViewShown() throws {
        let mockWindow = MockWindow()
        let mainViewController = MainViewController(bookmarkManager: bookmarksManager, autofillPopoverPresenter: DefaultAutofillPopoverPresenter())
        mockWindow.contentView = mainViewController.view

        vc = mainViewController.bookmarksBarViewController
        vc.viewWillAppear()
        vc.viewDidAppear()

        // When
        vc.importBookmarksClicked(self)

        // Then
        XCTAssertTrue(mockWindow.beginSheetCalled, "A sheet should be begun on the window")
    }

    @MainActor
    func testWhenThereAreBookmarks_ThenImportBookmarksButtonIsHidden() throws {
        // Given
        let boolmarkList = BookmarkList(topLevelEntities: [Bookmark(id: "test", url: "", title: "Something", isFavorite: false), Bookmark(id: "test", url: "", title: "Impori", isFavorite: false)])
        let vc = BookmarksBarViewController.create(tabCollectionViewModel: TabCollectionViewModel(), bookmarkManager: bookmarksManager, dragDropManager: .init(bookmarkManager: bookmarksManager))
        _=vc.view
        vc.viewWillAppear()
        vc.viewDidAppear()

        let expectation = XCTestExpectation(description: "Wait for list update")
        bookmarksManager.listPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { list in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        bookmarksManager.list = boolmarkList

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(vc.importBookmarksButton.isHidden)
    }

    @MainActor
    func testWhenThereAreNoBookmarks_AndbookmarkListEmpty_ThenImportBookmarksButtonIsNotShown() throws {
        // Given
        let vc = BookmarksBarViewController.create(tabCollectionViewModel: TabCollectionViewModel(), bookmarkManager: bookmarksManager, dragDropManager: .init(bookmarkManager: bookmarksManager))
        _=vc.view
        vc.viewWillAppear()
        vc.viewDidAppear()

        // Then
        XCTAssertTrue(vc.importBookmarksButton.isHidden)
    }

    @MainActor
    func testWhenThereAreNoBookmarks_ThenImportBookmarksButtonIsShown() throws {
        // Given
        let boolmarkList = BookmarkList(topLevelEntities: [])
        let vc = BookmarksBarViewController.create(tabCollectionViewModel: TabCollectionViewModel(), bookmarkManager: bookmarksManager, dragDropManager: .init(bookmarkManager: bookmarksManager))
        _=vc.view
        vc.viewWillAppear()
        vc.viewDidAppear()

        let expectation = XCTestExpectation(description: "Wait for list update")
        bookmarksManager.listPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { list in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        bookmarksManager.list = boolmarkList

        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(vc.importBookmarksButton.isHidden)
    }

}
