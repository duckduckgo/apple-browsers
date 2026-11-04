//
//  BookmarkListViewControllerSyncPromoTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@_spi(Testing) @testable import PixelKit

final class BookmarkListViewControllerSyncPromoTests: XCTestCase {

    func testWhenSyncPromoBecomesVisibleThenDisplayedPixelFiresOncePerAppearance() {
        let syncPromoManager = MockSyncPromoManager()
        let pixelFiring = PixelKitMock()
        let viewController = makeViewController(syncPromoManager: syncPromoManager, pixelFiring: pixelFiring)

        viewController.viewWillAppear()
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)

        syncPromoManager.isPromoActiveSubject.send(true)
        syncPromoManager.isPromoActiveSubject.send(false)
        syncPromoManager.isPromoActiveSubject.send(true)

        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.additionalParameters, ["source": "bookmarks"])

        viewController.viewWillDisappear()
        viewController.viewWillAppear()

        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), [SyncPromoPixelKitEvent.syncPromoDisplayed.name, SyncPromoPixelKitEvent.syncPromoDisplayed.name])
    }

    func testWhenSyncPromoIsActiveWithNoBookmarksThenDisplayedPixelIsNotFired() {
        let syncPromoManager = MockSyncPromoManager()
        syncPromoManager.isPromoActiveSubject.send(true)
        let pixelFiring = PixelKitMock()
        let viewController = makeViewController(bookmarks: [], syncPromoManager: syncPromoManager, pixelFiring: pixelFiring)

        viewController.viewWillAppear()

        XCTAssertFalse(pixelFiring.firedSyncPromoDisplayed)
    }

    private func makeViewController(bookmarks: [BaseBookmarkEntity] = [Bookmark(id: "1", url: "https://www.test1.com", title: "Bookmark #1", isFavorite: false)],
                                    syncPromoManager: SyncPromoManaging,
                                    pixelFiring: PixelKitMock) -> BookmarkListViewController {
        let bookmarkManager = MockBookmarkManager()
        bookmarkManager.list = BookmarkList(entities: bookmarks, topLevelEntities: bookmarks, favorites: [])
        let viewController = BookmarkListViewController(bookmarkManager: bookmarkManager,
                                                        dragDropManager: BookmarkDragDropManager(bookmarkManager: bookmarkManager),
                                                        pinningManager: MockPinningManager(),
                                                        syncPromoManager: syncPromoManager,
                                                        pixelFiring: pixelFiring)
        _ = viewController.view
        return viewController
    }
}

extension PixelKitMock {
    var firedSyncPromoDisplayed: Bool {
        actualFireCalls.contains { $0.pixel.name == SyncPromoPixelKitEvent.syncPromoDisplayed.name }
    }
}
