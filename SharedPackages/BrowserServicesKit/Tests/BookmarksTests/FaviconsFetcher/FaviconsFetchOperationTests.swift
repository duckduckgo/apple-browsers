//
//  FaviconsFetchOperationTests.swift
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

import BookmarksTestsUtils
import Common
import Foundation
import Persistence
import XCTest
@testable import Bookmarks

final class FaviconsFetchOperationTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var location: URL!

    var stateStore: MockFetcherStateStore!
    var fetcher: MockFaviconFetcher!
    var faviconStore: MockFaviconStore!

    var fetchOperation: FaviconsFetchOperation!

    override func setUp() {
        super.setUp()

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: location, model: model)
        bookmarksDatabase.loadStore()

        faviconStore = MockFaviconStore()
        fetcher = MockFaviconFetcher()
        stateStore = MockFetcherStateStore()

        fetchOperation = FaviconsFetchOperation(
            database: bookmarksDatabase,
            stateStore: stateStore,
            fetcher: fetcher,
            faviconStore: faviconStore
        )
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenGetBookmarkIDsThrowsErrorThenOperationThrowsError() async throws {
        stateStore.getError = StoreError()
        do {
            try await fetchOperation.fetchFavicons()
            XCTFail("Expected to throw error")
        } catch {}
    }

    func testThatMissingFaviconsAreFetchedAndStored() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        let fetchFaviconExpectation = expectation(description: "fetchFavicon")
        let storeFaviconExpectation = expectation(description: "storeFavicon")
        fetchFaviconExpectation.expectedFulfillmentCount = 3
        storeFaviconExpectation.expectedFulfillmentCount = 3

        fetcher.fetchFavicon = { _ in
            fetchFaviconExpectation.fulfill()
            return (Data(), nil)
        }

        faviconStore.storeFavicon = { _, _, _ in
            storeFaviconExpectation.fulfill()
        }

        try await fetchOperation.fetchFavicons()

        await fulfillment(of: [fetchFaviconExpectation, storeFaviconExpectation], timeout: 0.1)
        XCTAssertTrue(try stateStore.getBookmarkIDs().isEmpty)
    }

    func testWhenBookmarkHasFaviconThenItIsNotFetched() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        let fetchFaviconExpectation = expectation(description: "fetchFavicon")
        let storeFaviconExpectation = expectation(description: "storeFavicon")
        fetchFaviconExpectation.expectedFulfillmentCount = 2
        storeFaviconExpectation.expectedFulfillmentCount = 2

        fetcher.fetchFavicon = { _ in
            fetchFaviconExpectation.fulfill()
            return (Data(), nil)
        }

        faviconStore.hasFavicon = { domain in
            return domain == "1.com"
        }

        faviconStore.storeFavicon = { _, _, _ in
            storeFaviconExpectation.fulfill()
        }

        try await fetchOperation.fetchFavicons()

        await fulfillment(of: [fetchFaviconExpectation, storeFaviconExpectation], timeout: 0.1)
        XCTAssertTrue(try stateStore.getBookmarkIDs().isEmpty)
    }

    func testWhenStateIsEmptyThenFaviconsAreNotFetched() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs([])

        let fetchFaviconExpectation = expectation(description: "fetchFavicon")
        fetchFaviconExpectation.isInverted = true

        fetcher.fetchFavicon = { _ in
            fetchFaviconExpectation.fulfill()
            return (Data(), nil)
        }

        try await fetchOperation.fetchFavicons()

        await fulfillment(of: [fetchFaviconExpectation], timeout: 0.1)
    }

    func testWhenBookmarkWithIDIsNotPresentThenItIsIgnored() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["4"])

        let fetchFaviconExpectation = expectation(description: "fetchFavicon")
        fetchFaviconExpectation.isInverted = true

        fetcher.fetchFavicon = { _ in
            fetchFaviconExpectation.fulfill()
            return (Data(), nil)
        }

        try await fetchOperation.fetchFavicons()

        await fulfillment(of: [fetchFaviconExpectation], timeout: 0.1)
        XCTAssertTrue(try stateStore.getBookmarkIDs().isEmpty)
    }

    func testThatOnlyOneRequestPerDomainIsMade() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", url: "https://duckduckgo.com")
            Bookmark(id: "2", url: "https://wikipedia.org")
            Bookmark(id: "3", url: "https://google.com")
            Bookmark(id: "4", url: "https://duckduckgo.com/1")
            Bookmark(id: "5", url: "https://wikipedia.org/2")
            Bookmark(id: "6", url: "https://google.com/3")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        try stateStore.storeBookmarkIDs(["1", "2", "3", "4", "5", "6"])

        let fetchFaviconExpectation = expectation(description: "fetchFavicon")
        let storeFaviconExpectation = expectation(description: "storeFavicon")
        fetchFaviconExpectation.expectedFulfillmentCount = 3
        storeFaviconExpectation.expectedFulfillmentCount = 3

        fetcher.fetchFavicon = { _ in
            fetchFaviconExpectation.fulfill()
            return (Data(), nil)
        }

        faviconStore.storeFavicon = { _, _, _ in
            storeFaviconExpectation.fulfill()
        }

        try await fetchOperation.fetchFavicons()

        await fulfillment(of: [fetchFaviconExpectation, storeFaviconExpectation], timeout: 0.1)
        XCTAssertTrue(try stateStore.getBookmarkIDs().isEmpty)
    }

    func testWhenFaviconIsNotFoundThenItIsRemovedFromState() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        fetcher.fetchFavicon = { _ in
            return (nil, nil)
        }

        try await fetchOperation.fetchFavicons()
        XCTAssertTrue(try stateStore.getBookmarkIDs().isEmpty)
    }

    func testWhenFaviconFetchingThrowsNoInternetErrorThenItIsNotRemovedFromState() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        fetcher.fetchFavicon = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }

        try await fetchOperation.fetchFavicons()
        XCTAssertEqual(try stateStore.getBookmarkIDs(), ["1", "2", "3"])
    }

    func testWhenFaviconFetchingThrowsTimeoutErrorThenItIsNotRemovedFromState() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        fetcher.fetchFavicon = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        }

        try await fetchOperation.fetchFavicons()
        XCTAssertEqual(try stateStore.getBookmarkIDs(), ["1", "2", "3"])
    }

    func testWhenFaviconFetchingThrowsCancelledErrorThenItIsNotRemovedFromState() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        fetcher.fetchFavicon = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        }

        try await fetchOperation.fetchFavicons()
        XCTAssertEqual(try stateStore.getBookmarkIDs(), ["1", "2", "3"])
    }

    func testWhenFaviconFetchingThrowsErrorOtherThanNoInternetThenItIsRemovedFromState() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        fetcher.fetchFavicon = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
        }

        try await fetchOperation.fetchFavicons()
        XCTAssertEqual(try stateStore.getBookmarkIDs(), [])
    }

    func testWhenFaviconStoringThrowsErrorThenErrorIsRethrown() async throws {
        populateBookmarks()

        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        fetcher.fetchFavicon = { _ in
            return (Data(), nil)
        }

        faviconStore.storeFavicon = { _, _, _ in
            throw StoreError()
        }

        do {
            try await fetchOperation.fetchFavicons()
            XCTFail("Expected to throw error")
        } catch {
            XCTAssertTrue(error is StoreError)
        }
        XCTAssertEqual(try stateStore.getBookmarkIDs(), ["1", "2", "3"])
    }

    private func populateBookmarks() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", url: "https://1.com")
            Bookmark(id: "2", url: "https://2.com")
            Bookmark(id: "3", url: "https://3.com")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }
    }
}
