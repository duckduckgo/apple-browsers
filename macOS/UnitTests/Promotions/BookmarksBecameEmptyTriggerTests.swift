//
//  BookmarksBecameEmptyTriggerTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarksBecameEmptyTriggerTests: XCTestCase {

    private var bookmarkStore: BookmarkStoreMock!
    private var bookmarkManager: LocalBookmarkManager!
    private var observer: NSObjectProtocol?
    private var postCount = 0

    override func setUp() {
        super.setUp()
        bookmarkStore = BookmarkStoreMock()
        bookmarkManager = LocalBookmarkManager(bookmarkStore: bookmarkStore, appearancePreferences: .mock)
        postCount = 0
        observer = NotificationCenter.default.addObserver(forName: .bookmarksBecameEmpty, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeMainThread {
                self?.postCount += 1
            }
        }
    }

    override func tearDown() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        bookmarkManager = nil
        bookmarkStore = nil
        super.tearDown()
    }

    func testWhenLastBookmarkIsRemovedThenTriggerIsPosted() {
        // Given
        bookmarkStore.bookmarks = [Bookmark(id: "1", url: URL.duckDuckGo.absoluteString, title: "DDG", isFavorite: false)]
        bookmarkManager.loadBookmarks()

        // When
        bookmarkStore.bookmarks = []
        bookmarkManager.loadBookmarks()

        // Then
        XCTAssertEqual(postCount, 1)
    }

    func testWhenBookmarksAreFirstLoadedEmptyThenTriggerIsNotPosted() {
        // When
        bookmarkStore.bookmarks = []
        bookmarkManager.loadBookmarks()

        // Then
        XCTAssertEqual(postCount, 0)
    }

    func testWhenBookmarksStayEmptyThenTriggerIsNotPostedAgain() {
        // Given
        bookmarkStore.bookmarks = [Bookmark(id: "1", url: URL.duckDuckGo.absoluteString, title: "DDG", isFavorite: false)]
        bookmarkManager.loadBookmarks()
        bookmarkStore.bookmarks = []
        bookmarkManager.loadBookmarks()

        // When
        bookmarkManager.loadBookmarks()

        // Then
        XCTAssertEqual(postCount, 1)
    }

    func testWhenBookmarksRemainThenTriggerIsNotPosted() {
        // Given
        bookmarkStore.bookmarks = [Bookmark(id: "1", url: URL.duckDuckGo.absoluteString, title: "DDG", isFavorite: false)]
        bookmarkManager.loadBookmarks()

        // When
        bookmarkManager.loadBookmarks()

        // Then
        XCTAssertEqual(postCount, 0)
    }

    func testWhenNotificationIsPostedThenPromoTriggerIsEmitted() {
        var triggers: [PromoTrigger] = []
        let cancellable = PromoTrigger.triggerPublisher.sink { triggers.append($0) }

        NotificationCenter.default.post(name: .bookmarksBecameEmpty, object: nil)

        XCTAssertEqual(triggers, [.bookmarksBecameEmpty])
        cancellable.cancel()
    }
}
