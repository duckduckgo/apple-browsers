//
//  BookmarksFaviconsFetcher.swift
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

import Combine
import Common
import CoreData
import Foundation
import Persistence
import os.log

/**
 * This protocol abstracts favicons fetcher state storing interface.
 */
public protocol BookmarksFaviconsFetcherStateStoring: AnyObject {
    func getBookmarkIDs() throws -> Set<String>
    func storeBookmarkIDs(_ ids: Set<String>) throws
}

/**
 * This protocol abstracts a mechanism of fetching a single favicon
 */
public protocol FaviconFetching {
    /**
     * Fetch a favicon for a document specified by `url`.
     *
     * Returns optional favicon image data and an optional
     * favicon URL (if the fetcher is able to provide it).
     */
    func fetchFavicon(for url: URL) async throws -> (Data?, URL?)
}

/**
 * This protocol abstracts favicons storing interface provided by client apps.
 */
public protocol FaviconStoring {
    /**
     * Returns a boolean value telling whether the store has a cached favicon for a given `domain`.
     */
    @MainActor
    func hasFavicon(for domain: String) -> Bool

    /**
     * Stores favicon with `imageData` for document specified by `documentURL`.
     * Optional `url` parameter, if provided, specifies the URL of the favicon.
     */
    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws
}

/**
 * Errors that may be reported by `BookmarksFaviconsFetcher`.
 */
public enum BookmarksFaviconsFetcherError: CustomNSError {
    case failedToStoreBookmarkIDs(Error)
    case failedToRetrieveBookmarkIDs(Error)
    case other(Error)

    public static let errorDomain: String = "BookmarksFaviconsFetcherError"

    public var errorCode: Int {
        switch self {
        case .failedToStoreBookmarkIDs:
            return 1
        case .failedToRetrieveBookmarkIDs:
            return 2
        case .other:
            return 255
        }
    }

    public var underlyingError: Error {
        switch self {
        case .failedToStoreBookmarkIDs(let error), .failedToRetrieveBookmarkIDs(let error), .other(let error):
            return error
        }
    }
}

/**
 * This class manages fetching favicons for bookmarks updated by Sync.
 *
 * It takes modified and deleted bookmark IDs as input, fetches bookmarks' URLs,
 * extracts their domains and fetches favicons for those domains that don't have a favicon cached.
 */
public final class BookmarksFaviconsFetcher {

    @Published public private(set) var isFetchingInProgress: Bool = false
    public let fetchingDidFinishPublisher: AnyPublisher<Result<Void, Error>, Never>

    public init(
        database: CoreDataDatabase,
        stateStore: BookmarksFaviconsFetcherStateStoring,
        fetcher: FaviconFetching,
        faviconStore: FaviconStoring,
        errorEvents: EventMapping<BookmarksFaviconsFetcherError>?
    ) {
        self.database = database
        self.stateStore = stateStore
        self.fetcher = fetcher
        self.faviconStore = faviconStore
        self.errorEvents = errorEvents

        fetchingDidFinishPublisher = fetchingDidFinishSubject.eraseToAnyPublisher()

        isFetchingInProgressCancellable = Publishers
            .Merge(fetchingDidStartSubject.map({ true }), fetchingDidFinishSubject.map({ _ in false }))
            .prepend(false)
            .removeDuplicates()
            .assign(to: \.isFetchingInProgress, onWeaklyHeld: self)
    }

    /**
     * This function should be called right after favicons fetching was turned on.
     *
     * This function cancels any pending fetch operation prior to updating fetcher state.
     *
     * It sets up initial state by fetching all bookmarks' IDs.
     * After this function is called, `startFetching` can be called to go through
     * all bookmarks in the database and process those without a favicon.
     */
    public func initializeFetcherState() {
        cancelOngoingFetchingIfNeeded()
        operationQueue.addOperation {
            do {
                let allBookmarkIDs = self.fetchAllBookmarksUUIDs()
                try self.stateStore.storeBookmarkIDs(allBookmarkIDs)
            } catch {
                Logger.bookmarks.error("Error updating bookmark IDs: \(error.localizedDescription, privacy: .public)")
                if let fetcherError = error as? BookmarksFaviconsFetcherError {
                    self.errorEvents?.fire(fetcherError)
                } else {
                    self.errorEvents?.fire(.other(error))
                }
            }
        }
    }

    /**
     * This function should be called whenever sync receives new data.
     *
     * It is only responsible for updating the fetcher state. Actual fetching
     * needs `startFetching` to be called after calling this function.
     *
     * This function cancels any pending fetch operation prior to updating fetcher state.
     *
     * - Parameter modified: IDs of bookmarks that have been modified by Sync.
     * - Parameter deleted: IDs of bookmarks that have been deleted by Sync.
     */
    public func updateBookmarkIDs(modified: Set<String>, deleted: Set<String>) {
        cancelOngoingFetchingIfNeeded()
        operationQueue.addOperation {
            do {
                let ids = try self.stateStore.getBookmarkIDs().union(modified).subtracting(deleted)
                try self.stateStore.storeBookmarkIDs(ids)
            } catch {
                Logger.bookmarks.error("Error updating bookmark IDs: \(error.localizedDescription, privacy: .public)")
                if let fetcherError = error as? BookmarksFaviconsFetcherError {
                    self.errorEvents?.fire(fetcherError)
                } else {
                    self.errorEvents?.fire(.other(error))
                }
            }
        }
    }

    /**
     * Starts favicons fetch operation.
     *
     * This function cancels any pending fetch operation and schedules a new operation.
     */
    public func startFetching() {
        cancelOngoingFetchingIfNeeded()
        let operation = FaviconsFetchOperation(
            database: database,
            stateStore: stateStore,
            fetcher: fetcher,
            faviconStore: faviconStore
        )
        operation.didStart = { [weak self] in
            self?.fetchingDidStartSubject.send()
        }
        operation.didFinish = { [weak self] error in
            if let error {
                self?.fetchingDidFinishSubject.send(.failure(error))
                if let fetcherError = error as? BookmarksFaviconsFetcherError {
                    self?.errorEvents?.fire(fetcherError)
                } else if !(error is CancellationError) {
                    self?.errorEvents?.fire(.other(error))
                }
            } else {
                self?.fetchingDidFinishSubject.send(.success(()))
            }
        }
        operationQueue.addOperation(operation)
    }

    /**
     * Cancels any favicons fetching operations that may be in progress or scheduled for running.
     */
    public func cancelOngoingFetchingIfNeeded() {
        operationQueue.cancelAllOperations()
    }

    let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.duckduckgo.sync.bookmarksFaviconsFetcher"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private func fetchAllBookmarksUUIDs() -> Set<String> {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var ids = [String]()
        context.performAndWait {
            ids = BookmarkUtils.fetchAllBookmarksUUIDs(in: context)
        }
        return Set(ids)
    }

    private let errorEvents: EventMapping<BookmarksFaviconsFetcherError>?
    private let database: CoreDataDatabase
    private let stateStore: BookmarksFaviconsFetcherStateStoring
    private let fetcher: FaviconFetching
    private let faviconStore: FaviconStoring

    private var isFetchingInProgressCancellable: AnyCancellable?
    private let fetchingDidStartSubject = PassthroughSubject<Void, Never>()
    private let fetchingDidFinishSubject = PassthroughSubject<Result<Void, Error>, Never>()
}
