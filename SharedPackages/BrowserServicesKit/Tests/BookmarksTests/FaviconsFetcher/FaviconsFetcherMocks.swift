//
//  FaviconsFetcherMocks.swift
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

import Foundation
@testable import Bookmarks

struct StoreError: Error {}

class MockFaviconStore: FaviconStoring {
    var hasFavicon: (String) -> Bool = { _ in false }
    var storeFavicon: (Data, URL?, URL) async throws -> Void = { _, _, _ in }

    func hasFavicon(for domain: String) -> Bool {
        hasFavicon(domain)
    }

    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws {
        try await storeFavicon(imageData, url, documentURL)
    }
}

final class MockFaviconFetcher: FaviconFetching {
    var fetchFavicon: (URL) async throws -> (Data?, URL?) = { _ in (nil, nil) }

    func fetchFavicon(for url: URL) async throws -> (Data?, URL?) {
        try await fetchFavicon(url)
    }
}

final class MockFetcherStateStore: BookmarksFaviconsFetcherStateStoring {
    var bookmarkIDs: Set<String> = []
    var getError: Error?
    var storeError: Error?

    func getBookmarkIDs() throws -> Set<String> {
        if let getError {
            throw getError
        }
        return bookmarkIDs
    }

    func storeBookmarkIDs(_ ids: Set<String>) throws {
        if let storeError {
            throw storeError
        }
        bookmarkIDs = ids
    }
}
