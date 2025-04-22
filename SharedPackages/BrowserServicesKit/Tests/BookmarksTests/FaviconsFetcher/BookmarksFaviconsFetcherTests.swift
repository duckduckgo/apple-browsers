//
//  BookmarksFaviconsFetcherTests.swift
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

final class MockBookmarksFaviconsFetcherEventMapper: EventMapping<BookmarksFaviconsFetcherError> {
    static var errors: [BookmarksFaviconsFetcherError] = []

    public init() {
        super.init { event, _, _, _ in
            Self.errors.append(event)
        }
    }

    override init(mapping: @escaping EventMapping<BookmarksFaviconsFetcherError>.Mapping) {
        fatalError("Use init()")
    }
}

final class BookmarksFaviconsFetcherTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var location: URL!

    var stateStore: MockFetcherStateStore!
    var fetcher: MockFaviconFetcher!
    var faviconStore: MockFaviconStore!
    let eventMapper = MockBookmarksFaviconsFetcherEventMapper()

    var bookmarksFaviconsFetcher: BookmarksFaviconsFetcher!

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
        MockBookmarksFaviconsFetcherEventMapper.errors = []

        bookmarksFaviconsFetcher = BookmarksFaviconsFetcher(
            database: bookmarksDatabase,
            stateStore: stateStore,
            fetcher: fetcher,
            faviconStore: { self.faviconStore },
            errorEvents: eventMapper
        )
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testThatUpdateBookmarkIDsMakesUnionWithModifiedIDsAndSubtractsDeletedIDs() async throws {
        try stateStore.storeBookmarkIDs(["1", "2", "3"])

        bookmarksFaviconsFetcher.updateBookmarkIDs(modified: ["4", "5", "6"], deleted: [])
        await runAfterOperationsFinished {
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertEqual(ids, ["1", "2", "3", "4", "5", "6"])
            XCTAssertTrue(MockBookmarksFaviconsFetcherEventMapper.errors.isEmpty)
        }

        bookmarksFaviconsFetcher.updateBookmarkIDs(modified: ["2", "3", "4"], deleted: [])
        await runAfterOperationsFinished {
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertEqual(ids, ["1", "2", "3", "4", "5", "6"])
            XCTAssertTrue(MockBookmarksFaviconsFetcherEventMapper.errors.isEmpty)
        }

        bookmarksFaviconsFetcher.updateBookmarkIDs(modified: ["5", "6", "7"], deleted: ["1", "2", "3", "4"])
        await runAfterOperationsFinished {
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertEqual(ids, ["5", "6", "7"])
            XCTAssertTrue(MockBookmarksFaviconsFetcherEventMapper.errors.isEmpty)
        }

        bookmarksFaviconsFetcher.updateBookmarkIDs(modified: [], deleted: ["8"])
        await runAfterOperationsFinished {
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertEqual(ids, ["5", "6", "7"])
            XCTAssertTrue(MockBookmarksFaviconsFetcherEventMapper.errors.isEmpty)
        }
    }

    func testThatStateStoreSaveErrorIsReportedToEventMapperOnUpdateBookmarkIDs() async throws {
        try stateStore.storeBookmarkIDs(["1", "2", "3"])
        stateStore.storeError = BookmarksFaviconsFetcherError.failedToStoreBookmarkIDs(StoreError())

        bookmarksFaviconsFetcher.updateBookmarkIDs(modified: ["4", "5", "6"], deleted: [])
        await runAfterOperationsFinished {
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertEqual(ids, ["1", "2", "3"])
            XCTAssertEqual(MockBookmarksFaviconsFetcherEventMapper.errors.count, 1)
            let error = MockBookmarksFaviconsFetcherEventMapper.errors.first
            guard case .failedToStoreBookmarkIDs = error else {
                XCTFail("Unexpected error")
                return
            }
        }
    }

    func testThatStateStoreRetrieveErrorIsReportedToEventMapperOnUpdateBookmarkIDs() async throws {
        try stateStore.storeBookmarkIDs(["1", "2", "3"])
        stateStore.getError = BookmarksFaviconsFetcherError.failedToRetrieveBookmarkIDs(StoreError())

        bookmarksFaviconsFetcher.updateBookmarkIDs(modified: ["4", "5", "6"], deleted: [])
        await runAfterOperationsFinished {
            self.stateStore.getError = nil
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertEqual(ids, ["1", "2", "3"])
            XCTAssertEqual(MockBookmarksFaviconsFetcherEventMapper.errors.count, 1)
            let error = MockBookmarksFaviconsFetcherEventMapper.errors.first
            guard case .failedToRetrieveBookmarkIDs = error else {
                XCTFail("Unexpected error")
                return
            }
        }
    }

    func testWhenThereAreNoBookmarksThenInitializeFetcherStateStoresEmptySet() async throws {
        populateBookmarks {}

        bookmarksFaviconsFetcher.initializeFetcherState()
        await runAfterOperationsFinished {
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertTrue(ids.isEmpty)
            XCTAssertTrue(MockBookmarksFaviconsFetcherEventMapper.errors.isEmpty)
        }
    }

    func testThatInitializeFetcherStateStoresAllBookmarkIDs() async throws {
        populateBookmarks {
            Folder(id: "1") {}
            Folder(id: "2") {}
            Folder(id: "3") {
                Bookmark(id: "4")
                Bookmark(id: "5")
                Folder(id: "6") {
                    Bookmark(id: "7")
                    Bookmark(id: "8", isDeleted: true)
                }
            }
            Bookmark(id: "9")
        }

        bookmarksFaviconsFetcher.initializeFetcherState()
        await runAfterOperationsFinished {
            let ids = (try? self.stateStore.getBookmarkIDs()) ?? []
            XCTAssertEqual(ids, ["4", "5", "7", "9"])
            XCTAssertTrue(MockBookmarksFaviconsFetcherEventMapper.errors.isEmpty)
        }
    }

    func testWhenFetchingIsFinishedThenDidFinishPublisherEmitsEvent() async throws {
        var results: [Result<Void, Error>] = []
        let cancellable = bookmarksFaviconsFetcher.fetchingDidFinishPublisher.sink { results.append($0) }

        await bookmarksFaviconsFetcher.startFetching()

        await runAfterOperationsFinished {
            XCTAssertEqual(results.count, 1)
            guard case .success = results.first else {
                XCTFail("Expected success")
                return
            }
        }
        cancellable.cancel()
    }

    func testThatOperationCanBeCancelled() async throws {
        populateBookmarks {
            Bookmark(id: "1", url: "https://duckduckgo.com")
        }
        stateStore.bookmarkIDs = ["1"]
        fetcher.fetchFavicon = { _ in
            try await Task.sleep(nanoseconds: 100_000_000)
            return (nil, nil)
        }

        var results: [Result<Void, Error>] = []
        let cancellable = bookmarksFaviconsFetcher.fetchingDidFinishPublisher.sink { results.append($0) }

        await bookmarksFaviconsFetcher.startFetching()
        try await Task.sleep(nanoseconds: 10_000_000)
        bookmarksFaviconsFetcher.cancelOngoingFetchingIfNeeded()

        await runAfterOperationsFinished {
            XCTAssertEqual(results.count, 1)
            guard case .failure(let error) = results.first, error is CancellationError else {
                XCTFail("Expected CancellationError")
                return
            }
            // Cancellation errors are not reported
            XCTAssertTrue(MockBookmarksFaviconsFetcherEventMapper.errors.isEmpty)
        }
        cancellable.cancel()
    }

    func testThatCallToStartFetchingCancelsAnyRunningOperation() async throws {
        populateBookmarks {
            Bookmark(id: "1", url: "https://duckduckgo.com")
        }
        stateStore.bookmarkIDs = ["1"]
        fetcher.fetchFavicon = { _ in
            try await Task.sleep(nanoseconds: 100_000_000)
            return (nil, nil)
        }

        var results: [Result<Void, Error>] = []
        var isInProgressEvents: [Bool] = []
        let didFinishCancellable = bookmarksFaviconsFetcher.fetchingDidFinishPublisher.sink { results.append($0) }
        let isInProgressCancellable = bookmarksFaviconsFetcher.$isFetchingInProgress.sink { isInProgressEvents.append($0) }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.bookmarksFaviconsFetcher.startFetching()
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
            group.addTask {
                await self.bookmarksFaviconsFetcher.startFetching()
            }
        }

        await runAfterOperationsFinished {
            let successfulRuns = results.filter { result in
                if case .success = result {
                    return true
                }
                return false
            }
            XCTAssertEqual(successfulRuns.count, 1)
            XCTAssertEqual(results.count, 2)
            XCTAssertEqual(isInProgressEvents, [false, true, false, true, false])
        }
        didFinishCancellable.cancel()
        isInProgressCancellable.cancel()
    }

    // MARK: - Private

    private func runAfterOperationsFinished(_ block: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            bookmarksFaviconsFetcher.operationQueue.addBarrierBlock {
                block()
                continuation.resume()
            }
        }
    }

    private func populateBookmarks(@BookmarkTreeBuilder _ builder: () -> [BookmarkTreeNode]) {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree(builder: builder)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }
    }
}
