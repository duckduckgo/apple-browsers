//
//  CapturingHistoryViewBookmarksHandler.swift
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

import Foundation

@testable import DuckDuckGo_Privacy_Browser

final class CapturingHistoryViewBookmarksHandler: HistoryViewBookmarksHandling {
    func isUrlBookmarked(url: URL) -> Bool {
        isUrlBookmarkedCalls.append(url)
        return isUrlBookmarked(url)
    }

    func isUrlFavorited(url: URL) -> Bool {
        isUrlFavoritedCalls.append(url)
        return isUrlFavorited(url)
    }

    func getBookmark(for url: URL) -> Bookmark? {
        getBookmarkCalls.append(url)
        return getBookmark(url)
    }

    func markAsFavorite(_ bookmark: Bookmark) {
        markAsFavoriteCalls.append(bookmark)
        markAsFavoriteImpl(bookmark)
    }

    func addNewBookmarks(for websiteInfos: [WebsiteInfo]) {
        addNewBookmarksCalls.append(websiteInfos)
        addNewBookmarks(websiteInfos)
    }

    func addNewFavorite(for url: URL, title: String) {
        addNewFavoriteCalls.append(.init(url, title))
        addNewFavorite(url, title)
    }

    var isUrlBookmarkedCalls: [URL] = []
    var isUrlBookmarked: (URL) -> Bool = { _ in false }

    var isUrlFavoritedCalls: [URL] = []
    var isUrlFavorited: (URL) -> Bool = { _ in false }

    var getBookmarkCalls: [URL] = []
    var getBookmark: (URL) -> Bookmark? = { _ in nil }

    var markAsFavoriteCalls: [Bookmark] = []
    var markAsFavoriteImpl: (Bookmark) -> Void = { _ in }

    var addNewBookmarksCalls: [[WebsiteInfo]] = []
    var addNewBookmarks: ([WebsiteInfo]) -> Void = { _ in }

    struct AddNewFavoriteCall: Equatable {
        let url: URL
        let title: String

        init(_ url: URL, _ title: String) {
            self.url = url
            self.title = title
        }
    }
    var addNewFavoriteCalls: [AddNewFavoriteCall] = []
    var addNewFavorite: (URL, String) -> Void = { _, _ in }
}
