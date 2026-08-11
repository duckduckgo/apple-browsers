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

import Combine
import Common
import FeatureFlags_macOS
import FoundationExtensions
import History
import HistoryView
import PrivacyConfig
import SharedTestUtilities
import XCTest

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
        let fireCoordinator = FireCoordinator(tld: TLD(),
                                              featureFlagger: Application.appDelegate.featureFlagger,
                                              historyCoordinating: HistoryCoordinatingMock(),
                                              visualizeFireAnimationDecider: nil,
                                              onboardingContextualDialogsManager: nil,
                                              fireproofDomains: MockFireproofDomains(),
                                              faviconManagement: FaviconManagerMock(),
                                              windowControllersManager: WindowControllersManagerMock(),
                                              dataClearingPreferences: Application.appDelegate.dataClearingPreferences,
                                              pixelFiring: nil,
                                              historyProvider: MockHistoryViewDataProvider())

        let mainViewController = MainViewController(
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
            bookmarkManager: bookmarksManager,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: MockFeatureFlagger()),
            fireCoordinator: fireCoordinator
        )
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
        let vc = BookmarksBarViewController.create(
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
            bookmarkManager: bookmarksManager,
            dragDropManager: .init(bookmarkManager: bookmarksManager),
            pinningManager: MockPinningManager(),
            featureFlagger: MockFeatureFlagger()
        )
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
        let vc = BookmarksBarViewController.create(
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
            bookmarkManager: bookmarksManager,
            dragDropManager: .init(bookmarkManager: bookmarksManager),
            pinningManager: MockPinningManager(),
            featureFlagger: MockFeatureFlagger()
        )
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
        let vc = BookmarksBarViewController.create(
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
            bookmarkManager: bookmarksManager,
            dragDropManager: .init(bookmarkManager: bookmarksManager),
            pinningManager: MockPinningManager(),
            featureFlagger: MockFeatureFlagger()
        )
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

    @MainActor
    func testWhenReorderByNameIsSelectedFromBookmarksBarThenMainWindowUndoManagerReceivesAction() throws {
        // GIVEN
        let zulu = Bookmark(id: "zulu", url: "https://zulu.example", title: "Zulu", isFavorite: false)
        let alpha = BookmarkFolder(id: "alpha", title: "Alpha")
        bookmarksManager.list = BookmarkList(entities: [zulu], topLevelEntities: [zulu, alpha])
        bookmarksManager.sortMode = .nameDescending
        let controller = BookmarksBarViewController.create(
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
            bookmarkManager: bookmarksManager,
            dragDropManager: .init(bookmarkManager: bookmarksManager),
            pinningManager: MockPinningManager(),
            featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.bookmarksReorderByName.rawValue: true]))
        let window = NSWindow(contentViewController: controller)
        let undoManager = try XCTUnwrap(window.undoManager)
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        let menuItem = try XCTUnwrap(menu.items.first(where: { $0.title == UserText.bookmarksBarContextMenuReorderByName }))
        let target = try XCTUnwrap(menuItem.target)
        let action = try XCTUnwrap(menuItem.action)

        // WHEN
        _ = target.perform(action, with: menuItem)

        // THEN
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, UserText.bookmarksUndoActionReorderByName)
    }

    @MainActor
    func testWhenBookmarksBarMenuIsHostedInChildWindowThenUndoManagerResolvesToTopLevelWindow() {
        // GIVEN
        let parentWindow = NSWindow()
        let childWindow = BookmarksBarMenuWindow()
        let controller = BookmarksBarMenuViewController(
            bookmarkManager: bookmarksManager,
            dragDropManager: .init(bookmarkManager: bookmarksManager))
        childWindow.contentViewController = controller
        parentWindow.addChildWindow(childWindow, ordered: .above)
        defer { parentWindow.removeChildWindow(childWindow) }

        // THEN
        XCTAssertTrue(controller.undoManager === parentWindow.undoManager)
        XCTAssertFalse(controller.undoManager === childWindow.undoManager)
    }

    @MainActor
    func testWhenBookmarkListHasHostWindowThenUndoManagerResolvesToHostWindow() {
        // GIVEN
        let hostWindow = NSWindow()
        let controller = BookmarkListViewController(
            bookmarkManager: bookmarksManager,
            dragDropManager: .init(bookmarkManager: bookmarksManager),
            pinningManager: MockPinningManager())

        // WHEN
        controller.hostWindow = hostWindow

        // THEN
        XCTAssertTrue(controller.undoManager === hostWindow.undoManager)
    }

}
