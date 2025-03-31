//
//  FaviconsFetchOperation.swift
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
import Combine
import Common
import CoreData
import Persistence
import os.log

final class FaviconsFetchOperation: Operation, @unchecked Sendable {

    enum FaviconFetchError: Error {
        case connectionError
        case requestError
    }

    enum Const {
        static let maximumConcurrentFetches = 10
    }

    var didStart: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didStart
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didStart = newValue
        }
    }

    var didFinish: ((Error?) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _didFinish
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _didFinish = newValue
        }
    }

    init(
        database: CoreDataDatabase,
        stateStore: BookmarksFaviconsFetcherStateStoring,
        fetcher: FaviconFetching,
        faviconStore: FaviconStoring
    ) {
        self.database = database
        self.stateStore = stateStore
        self.fetcher = fetcher
        self.faviconStore = faviconStore
    }

    override func start() {
        guard !isCancelled else {
            isExecuting = false
            isFinished = true
            return
        }

        isExecuting = true
        isFinished = false

        didStart?()

        Task {
            defer {
                isExecuting = false
                isFinished = true
            }

            do {
                try await fetchFavicons()
                didFinish?(nil)
            } catch {
                didFinish?(error)
            }
        }
    }

    func fetchFavicons() async throws {
        var (bookmarkDomains, idsToProcess) = try await MainActor.run { () -> (BookmarkDomains?, Set<String>) in
            let idsToProcess = try stateStore.getBookmarkIDs()

            guard !idsToProcess.isEmpty else {
                Logger.bookmarks.debug("No new Favicons to fetch")
                return (nil, [])
            }
            Logger.bookmarks.debug("Favicons Fetch Operation started")

            var bookmarkDomains = mapBookmarkDomainsToUUIDs(for: idsToProcess)
            bookmarkDomains.filterDomains { [weak self] domain in
                self?.faviconStore.hasFavicon(for: domain) == false
            }
            return (bookmarkDomains, idsToProcess)
        }

        defer {
            Logger.bookmarks.debug("Favicons Fetch Operation finished")
        }
        guard let bookmarkDomains else {
            return
        }

        idsToProcess = bookmarkDomains.allUUIDs

        try checkCancellation()

        var allDomains = bookmarkDomains.allDomains

        guard !allDomains.isEmpty else {
            Logger.bookmarks.debug("No favicons to fetch")
            try stateStore.storeBookmarkIDs(idsToProcess)
            return
        }
        Logger.bookmarks.debug("Will try to fetch favicons for \(allDomains.count, privacy: .public) domains")

        while !allDomains.isEmpty {
            let numberOfDomainsToFetch = min(Const.maximumConcurrentFetches, allDomains.count)
            let domainsToFetch = Array(allDomains.prefix(upTo: numberOfDomainsToFetch))
            allDomains = Array(allDomains.dropFirst(numberOfDomainsToFetch))

            let handledIds = try await withThrowingTaskGroup(of: Set<String>.self, returning: Set<String>.self) { group in
                for domain in domainsToFetch {
                    let url = URL(string: "\(URL.NavigationalScheme.https.separated())\(domain)")
                    if let idsForDomain = bookmarkDomains.ids(for: domain), let url {
                        group.addTask { [weak self] in
                            guard let self else {
                                return []
                            }
                            return try await self.handleDomain(with: url, bookmarkIDs: idsForDomain)
                        }
                    }
                }

                var results = Set<String>()
                for try await value in group {
                    results.formUnion(value)
                }
                return results
            }

            idsToProcess.subtract(handledIds)
            try stateStore.storeBookmarkIDs(idsToProcess)

            try checkCancellation()
        }
    }

    /**
     * This function fetches a favicon for a domain specified by `url`, required for bookmarks with `bookmarkIDs`.
     *
     * Returns an array of procesed bookmarks, which is either the original `bookmarkIDs` in case
     * of success, favicon not found or request error, or an empty array in case of cancellation
     * or connection error.
     */
    private func handleDomain(with url: URL, bookmarkIDs: Set<String>) async throws -> Set<String> {
        do {
            try await self.fetchAndStoreFavicon(for: url)
            return bookmarkIDs
        } catch is CancellationError {
            return []
        } catch let error as FaviconFetchError {
            switch error {
            case .connectionError:
                return []
            case .requestError:
                return bookmarkIDs
            }
        }

    }

    private func fetchAndStoreFavicon(for url: URL) async throws {
        let fetchResult: (Data?, URL?)
        do {
            fetchResult = try await fetcher.fetchFavicon(for: url)
        } catch {
            let nsError = error as NSError
            // if user is offline, we want to retry later
            let temporaryErrorCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorCancelled]
            if nsError.domain == NSURLErrorDomain, temporaryErrorCodes.contains(nsError.code) {
                throw FaviconFetchError.connectionError
            }
            throw FaviconFetchError.requestError
        }

        do {
            let (imageData, imageURL) = fetchResult
            if let imageData {
                Logger.bookmarks.debug("Favicon found for \(url.absoluteString, privacy: .public)")
                try await faviconStore.storeFavicon(imageData, with: imageURL, for: url)
            } else {
                Logger.bookmarks.debug("Favicon not found for \(url.absoluteString, privacy: .public)")
            }

            try checkCancellation()
        } catch is CancellationError {
            Logger.bookmarks.debug("Favicon fetching cancelled")
            throw CancellationError()
        } catch {
            Logger.bookmarks.debug("Error storing favicon for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    private func mapBookmarkDomainsToUUIDs(for uuids: any Sequence & CVarArg) -> BookmarkDomains {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K IN %@ AND %K == NO AND %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.uuid), uuids,
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.propertiesToFetch = [#keyPath(BookmarkEntity.uuid), #keyPath(BookmarkEntity.url)]
        request.relationshipKeyPathsForPrefetching = [#keyPath(BookmarkEntity.favoriteFolders), #keyPath(BookmarkEntity.parent)]

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var bookmarkDomains: BookmarkDomains!
        context.performAndWait {
            let bookmarks = (try? context.fetch(request)) ?? []
            bookmarkDomains = .init(bookmarks: bookmarks)
        }
        return bookmarkDomains
    }

    // MARK: - Overrides

    override var isAsynchronous: Bool { true }

    override var isExecuting: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isExecuting
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isExecuting))
            _isExecuting = newValue
            didChangeValue(forKey: #keyPath(isExecuting))
        }
    }

    override var isFinished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isFinished
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            willChangeValue(forKey: #keyPath(isFinished))
            _isFinished = newValue
            didChangeValue(forKey: #keyPath(isFinished))
        }
    }

    private let lock = NSRecursiveLock()

    private let database: CoreDataDatabase
    private let stateStore: BookmarksFaviconsFetcherStateStoring
    private let fetcher: FaviconFetching
    private let faviconStore: FaviconStoring

    private var _isExecuting: Bool = false
    private var _isFinished: Bool = false
    private var _didStart: (() -> Void)?
    private var _didFinish: ((Error?) -> Void)?
    private var _didReceiveHTTPRequestError: ((Error) -> Void)?
}

/**
 * Helper struct that helps organize bookmarks to be processed by the fetch operation.
 *
 * Fetcher first processes favorites, then top level bookmarks and then all other bookmarks.
 */
struct BookmarkDomains {
    var favoritesDomainsToUUIDs: [String: Set<String>]
    var topLevelBookmarksDomainsToUUIDs: [String: Set<String>]
    var otherBookmarksDomainsToUUIDs: [String: Set<String>]

    func ids(for domain: String) -> Set<String>? {
        favoritesDomainsToUUIDs[domain] ?? topLevelBookmarksDomainsToUUIDs[domain] ?? otherBookmarksDomainsToUUIDs[domain]
    }

    var allDomains: [String] {
        Array(favoritesDomainsToUUIDs.keys) + topLevelBookmarksDomainsToUUIDs.keys + otherBookmarksDomainsToUUIDs.keys
    }

    var allUUIDs: Set<String> {
        Set(otherBookmarksDomainsToUUIDs.values.flatMap { $0 })
            .union(favoritesDomainsToUUIDs.values.flatMap { $0 })
            .union(topLevelBookmarksDomainsToUUIDs.values.flatMap { $0 })
    }

    mutating func filterDomains(by isIncluded: (String) -> Bool) {
        otherBookmarksDomainsToUUIDs = otherBookmarksDomainsToUUIDs.filter { isIncluded($0.key) }
        favoritesDomainsToUUIDs = favoritesDomainsToUUIDs.filter { isIncluded($0.key) }
        topLevelBookmarksDomainsToUUIDs = topLevelBookmarksDomainsToUUIDs.filter { isIncluded($0.key) }
    }

    init(bookmarks: [BookmarkEntity]) {
        var favoritesDomainsToUUIDs = [String: Set<String>]()
        var topLevelBookmarksDomainsToUUIDs = [String: Set<String>]()
        var otherBookmarksDomainsToUUIDs = [String: Set<String>]()

        bookmarks.forEach { bookmark in
            guard let uuid = bookmark.uuid, let domain = bookmark.url.flatMap(URL.init(string:))?.host else {
                return
            }

            if let favoritesUUIDs = favoritesDomainsToUUIDs[domain] {
                favoritesDomainsToUUIDs[domain] = favoritesUUIDs.union([uuid])
            } else if (bookmark.favoriteFolders?.count ?? 0) > 0 {
                let topLevelUUIDs = topLevelBookmarksDomainsToUUIDs.removeValue(forKey: domain) ?? []
                let otherUUIDs = otherBookmarksDomainsToUUIDs.removeValue(forKey: domain) ?? []
                favoritesDomainsToUUIDs[domain] = topLevelUUIDs.union(otherUUIDs).union([uuid])
            } else if let topLevelUUIDs = topLevelBookmarksDomainsToUUIDs[domain] {
                topLevelBookmarksDomainsToUUIDs[domain] = topLevelUUIDs.union([uuid])
            } else if bookmark.parent?.uuid == BookmarkEntity.Constants.rootFolderID {
                let otherUUIDs = otherBookmarksDomainsToUUIDs.removeValue(forKey: domain) ?? []
                topLevelBookmarksDomainsToUUIDs[domain] = otherUUIDs.union([uuid])
            } else if let uuids = otherBookmarksDomainsToUUIDs[domain] {
                otherBookmarksDomainsToUUIDs[domain] = uuids.union([uuid])
            } else {
                otherBookmarksDomainsToUUIDs[domain] = [uuid]
            }
        }

        self.init(
            favoritesDomainsToUUIDs: favoritesDomainsToUUIDs,
            topLevelBookmarksDomainsToUUIDs: topLevelBookmarksDomainsToUUIDs,
            otherBookmarksDomainsToUUIDs: otherBookmarksDomainsToUUIDs
        )
    }

    init(
        favoritesDomainsToUUIDs: [String: Set<String>],
        topLevelBookmarksDomainsToUUIDs: [String: Set<String>],
        otherBookmarksDomainsToUUIDs: [String: Set<String>]) {
        self.favoritesDomainsToUUIDs = favoritesDomainsToUUIDs
        self.topLevelBookmarksDomainsToUUIDs = topLevelBookmarksDomainsToUUIDs
        self.otherBookmarksDomainsToUUIDs = otherBookmarksDomainsToUUIDs
    }
}
