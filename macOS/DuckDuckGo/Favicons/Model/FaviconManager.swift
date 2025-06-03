//
//  FaviconManager.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Bookmarks
import Cocoa
import Combine
import BrowserServicesKit
import Common
import History
import CoreImage

protocol FaviconManagement: AnyObject {

    @MainActor
    var isCacheLoaded: Bool { get }

    var faviconsLoadedPublisher: Published<Bool>.Publisher { get }

    @MainActor
    func loadFavicons() async throws

    @MainActor
    func handleFaviconLinks(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL) async -> Favicon?

    @MainActor
    func handleFaviconsByDocumentUrl(_ faviconsByDocumentUrl: [URL: [Favicon]]) async

    @MainActor
    func getCachedFaviconURL(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL?

    @MainActor
    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?

    @MainActor
    func getCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?

    @MainActor
    func getCachedFavicon(forDomainOrAnySubdomain domain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?

    @MainActor
    func burn(except: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async

    @MainActor
    func burnDomains(_ domains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins: Set<String>,
                     exceptExistingHistory history: BrowsingHistory,
                     tld: TLD) async
}

/**
 * This extension provides convenience functions for fetching favicons at a specific size category.
 *
 * All functions in this extension call their more verbose equivalents with `fallBackToSmaller = false`.
 */
extension FaviconManagement {
    @MainActor
    func getCachedFaviconURL(for documentUrl: URL, sizeCategory: Favicon.SizeCategory) -> URL? {
        getCachedFaviconURL(for: documentUrl, sizeCategory: sizeCategory, fallBackToSmaller: false)
    }

    @MainActor
    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory) -> Favicon? {
        getCachedFavicon(for: documentUrl, sizeCategory: sizeCategory, fallBackToSmaller: false)
    }

    @MainActor
    func getCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory) -> Favicon? {
        getCachedFavicon(for: host, sizeCategory: sizeCategory, fallBackToSmaller: false)
    }

    @MainActor
    func getCachedFavicon(forDomainOrAnySubdomain domain: String, sizeCategory: Favicon.SizeCategory) -> Favicon? {
        getCachedFavicon(forDomainOrAnySubdomain: domain, sizeCategory: sizeCategory, fallBackToSmaller: false)
    }
}

final class FaviconManager: FaviconManagement {

    enum CacheType {
        case standard
        case inMemory
    }

    init(
        cacheType: CacheType,
        bookmarkManager: BookmarkManager,
        imageCache: ((FaviconStoring) -> FaviconImageCaching)? = nil,
        referenceCache: ((FaviconStoring) -> FaviconReferenceCaching)? = nil
    ) {
        switch cacheType {
        case .standard:
            store = FaviconStore()
        case .inMemory:
            store = FaviconNullStore()
        }
        self.bookmarkManager = bookmarkManager
        self.imageCache = imageCache?(store) ?? FaviconImageCache(faviconStoring: store)
        self.referenceCache = referenceCache?(store) ?? FaviconReferenceCache(faviconStoring: store)

        Task {
            try? await loadFavicons()
        }
    }

    private(set) var store: FaviconStoring

    private let bookmarkManager: BookmarkManager
    private let faviconURLSession = URLSession(configuration: .ephemeral)

    @Published private var faviconsLoaded = false
    var faviconsLoadedPublisher: Published<Bool>.Publisher { $faviconsLoaded }

    func loadFavicons() async throws {
        try await imageCache.load()
        await imageCache.cleanOld(except: FireproofDomains.shared, bookmarkManager: bookmarkManager)
        try await referenceCache.load()
        await referenceCache.cleanOld(except: FireproofDomains.shared, bookmarkManager: bookmarkManager)
        faviconsLoaded = true
    }

    var isCacheLoaded: Bool {
        imageCache.loaded && referenceCache.loaded
    }

    @MainActor
    private func awaitFaviconsLoaded() async {
        if faviconsLoaded { return }
        await withCheckedContinuation { continuation in
            $faviconsLoaded
                .filter { $0 == true }
                .first()
                .promise()
                .receive { _ in
                    continuation.resume(returning: ())
                }
        }
    }

    // MARK: - Fetching & Cache

    private let imageCache: FaviconImageCaching
    private let referenceCache: FaviconReferenceCaching

    func handleFaviconLinks(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL) async -> Favicon? {
        // Manually add favicon.ico into links
        let faviconLinks = createFallbackLinksIfNeeded(faviconLinks, documentUrl: documentUrl)

        await awaitFaviconsLoaded()
        // Fetch favicons if needed
        let faviconLinksToFetch = await filteringAlreadyFetchedFaviconLinks(from: faviconLinks)
        let newFavicons = await fetchFavicons(faviconLinks: faviconLinksToFetch, documentUrl: documentUrl)
        let favicon = await cacheFavicons(newFavicons, faviconURLs: faviconLinks.lazy.map(\.href), for: documentUrl)

        return favicon
    }

    func handleFaviconsByDocumentUrl(_ faviconsByDocumentUrl: [URL: [Favicon]]) async {
        // Insert new favicons to cache
        imageCache.insert(faviconsByDocumentUrl.values.reduce([], +))

        // Pick most suitable favicons
        for (documentUrl, newFavicons) in faviconsByDocumentUrl {
            let weekAgo = Date.weekAgo
            let cachedFavicons = imageCache.getFavicons(with: newFavicons.lazy.map(\.url))?
                .filter { favicon in
                    favicon.dateCreated > weekAgo
                }

            await handleFaviconReferenceCacheInsertion(documentURL: documentUrl, cachedFavicons: cachedFavicons ?? [], newFavicons: newFavicons)
        }
    }

    @MainActor
    @discardableResult private func handleFaviconReferenceCacheInsertion(documentURL: URL, cachedFavicons: [Favicon], newFavicons: [Favicon]) async -> Favicon? {
        let noFaviconPickedYet = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .small) == nil
        let newFaviconLoaded = !newFavicons.isEmpty
        let currentSmallFaviconUrl = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .small)
        let currentMediumFaviconUrl = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .medium)
        let cachedFaviconUrls = cachedFavicons.map {$0.url}
        let faviconsOutdated: Bool = {
            if let currentSmallFaviconUrl = currentSmallFaviconUrl, !cachedFaviconUrls.contains(currentSmallFaviconUrl) {
                return true
            }
            if let currentMediumFaviconUrl = currentMediumFaviconUrl, !cachedFaviconUrls.contains(currentMediumFaviconUrl) {
                return true
            }
            return false
        }()

        // If we haven't pick a favicon yet or there is a new favicon loaded or favicons are outdated
        // Pick the most suitable favicons. Otherwise use cached references
        if noFaviconPickedYet || newFaviconLoaded || faviconsOutdated {
            let sortedCachedFavicons = cachedFavicons.sorted(by: { $0.longestSide < $1.longestSide })
            let mediumFavicon = FaviconSelector.getMostSuitableFavicon(for: .medium, favicons: sortedCachedFavicons)
            let smallFavicon = FaviconSelector.getMostSuitableFavicon(for: .small, favicons: sortedCachedFavicons)
            referenceCache.insert(faviconUrls: (smallFavicon?.url, mediumFavicon?.url), documentUrl: documentURL)
            return smallFavicon
        } else {
            guard let currentSmallFaviconUrl = currentSmallFaviconUrl,
                  let cachedFavicon = imageCache.get(faviconUrl: currentSmallFaviconUrl) else {
                      return nil
                  }

            return cachedFavicon
        }
    }

    func getCachedFaviconURL(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL? {
        guard let faviconURL = referenceCache.getFaviconUrl(for: documentUrl, sizeCategory: sizeCategory) else {
            guard fallBackToSmaller, let smallerSizeCategory = sizeCategory.smaller else {
                return nil
            }
            return getCachedFaviconURL(for: documentUrl, sizeCategory: smallerSizeCategory, fallBackToSmaller: fallBackToSmaller)
        }
        return faviconURL
    }

    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        guard let faviconURL = referenceCache.getFaviconUrl(for: documentUrl, sizeCategory: sizeCategory) else {
            guard fallBackToSmaller, let smallerSizeCategory = sizeCategory.smaller else {
                return nil
            }
            return getCachedFavicon(for: documentUrl, sizeCategory: smallerSizeCategory, fallBackToSmaller: fallBackToSmaller)
        }

        return imageCache.get(faviconUrl: faviconURL)
    }

    func getCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        guard let faviconUrl = referenceCache.getFaviconUrl(for: host, sizeCategory: sizeCategory) else {
            guard fallBackToSmaller, let smallerSizeCategory = sizeCategory.smaller else {
                return nil
            }
            return getCachedFavicon(for: host, sizeCategory: smallerSizeCategory, fallBackToSmaller: fallBackToSmaller)
        }

        return imageCache.get(faviconUrl: faviconUrl)
    }

    func getCachedFavicon(forDomainOrAnySubdomain domain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        if let favicon = getCachedFavicon(for: domain, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller) {
            return favicon
        }

        let availableSubdomains = referenceCache.hostReferences.keys + referenceCache.urlReferences.keys.compactMap { $0.host }
        let subdomain = availableSubdomains.first { subdomain in
            subdomain.hasSuffix(domain)
        }

        if let subdomain {
            return getCachedFavicon(for: subdomain, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller)
        }
        return nil
    }

    // MARK: - Burning

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String> = []) async {
        await referenceCache.burn(except: fireproofDomains, bookmarkManager: bookmarkManager, savedLogins: savedLogins)
        await imageCache.burn(except: fireproofDomains, bookmarkManager: bookmarkManager, savedLogins: savedLogins)
    }

    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins: Set<String> = [],
                     exceptExistingHistory history: BrowsingHistory,
                     tld: TLD) async {
        let existingHistoryDomains = Set(history.compactMap { $0.url.host })

        await referenceCache.burnDomains(baseDomains, exceptBookmarks: bookmarkManager,
                                         exceptSavedLogins: exceptSavedLogins,
                                         exceptHistoryDomains: existingHistoryDomains,
                                         tld: tld)
        await imageCache.burnDomains(baseDomains,
                                     exceptBookmarks: bookmarkManager,
                                     exceptSavedLogins: exceptSavedLogins,
                                     exceptHistoryDomains: existingHistoryDomains,
                                     tld: tld)
    }

    // MARK: - Private

    private func createFallbackLinksIfNeeded(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL) -> [FaviconUserScript.FaviconLink] {
        let validSchemes: [URL.NavigationalScheme?] = [.http, .https]
        guard faviconLinks.isEmpty,
              let root = documentUrl.root?.toHttps(),
              validSchemes.contains(documentUrl.navigationalScheme) else {
            return faviconLinks
        }
        return [
            FaviconUserScript.FaviconLink(href: root.appending("favicon.ico"), rel: "favicon.ico")
        ]
    }

    private func filteringAlreadyFetchedFaviconLinks(from faviconLinks: [FaviconUserScript.FaviconLink]) async -> [FaviconUserScript.FaviconLink] {
        let urlsToLinks = faviconLinks.reduce(into: [URL: FaviconUserScript.FaviconLink]()) { result, faviconLink in
            result[faviconLink.href] = faviconLink
        }
        let weekAgo = Date.weekAgo
        let cachedFavicons = await imageCache.getFavicons(with: urlsToLinks.keys)?
            .filter { favicon in
                favicon.dateCreated > weekAgo
            } ?? []
        let cachedUrls = Set(cachedFavicons.map(\.url))

        let nonCachedFavicons = urlsToLinks.filter { url, _ in
            !cachedUrls.contains(url)
        }.values

        return Array(nonCachedFavicons)
    }

    private func fetchFavicons(faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL) async -> [Favicon] {
        guard !faviconLinks.isEmpty else { return [] }

        return await withTaskGroup(of: Favicon?.self) { [faviconURLSession] group in
            for faviconLink in faviconLinks {
                let faviconUrl = faviconLink.href
                group.addTask {
                    guard let data = try? await faviconURLSession.data(from: faviconUrl).0 else { return nil }

                    let favicon = Favicon(identifier: UUID(),
                                          url: faviconUrl,
                                          image: NSImage(dataUsingCIImage: data),
                                          relationString: faviconLink.rel,
                                          documentUrl: documentUrl,
                                          dateCreated: Date())
                    return favicon
                }
            }
            var favicons = [Favicon]()
            for await result in group {
                if let favicon = result {
                    favicons.append(favicon)
                }
            }

            return favicons
        }
    }

    @MainActor
    @discardableResult private func cacheFavicons(_ favicons: [Favicon], faviconURLs: [URL], for documentUrl: URL) async -> Favicon? {
        // Insert new favicons to cache
        imageCache.insert(favicons)
        // Pick most suitable favicons
        let cachedFavicons = imageCache.getFavicons(with: faviconURLs)?.filter { $0.dateCreated > Date.weekAgo }

        return await handleFaviconReferenceCacheInsertion(
            documentURL: documentUrl,
            cachedFavicons: cachedFavicons ?? [],
            newFavicons: favicons
        )
    }
}

extension FaviconManager: Bookmarks.FaviconStoring {

    func hasFavicon(for domain: String) -> Bool {
        guard let url = domain.url, let faviconURL = self.referenceCache.getFaviconUrl(for: url, sizeCategory: .small) else {
            return false
        }
        return self.imageCache.get(faviconUrl: faviconURL) != nil
    }

    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws {
        guard let image = NSImage(data: imageData) else {
            return
        }

        await self.awaitFaviconsLoaded()

        // If URL is not provided, we don't know the favicon URL,
        // so we use a made up URL that identifies sync-related favicon.
        let faviconURL = url ?? documentURL.appendingPathComponent("ddgsync-favicon.ico")

        let favicon = Favicon(identifier: UUID(),
                              url: faviconURL,
                              image: image,
                              relationString: "favicon",
                              documentUrl: documentURL,
                              dateCreated: Date())

        await cacheFavicons([favicon], faviconURLs: [faviconURL], for: documentURL)
    }
}

fileprivate extension NSImage {
    /**
     * This function attempts to initialize `NSImage` from `CIImage`.
     *
     * This helps to preserve transparency on some PNG images, and fixes
     * storing `NSImage` initialized with `ico` files in NSKeyedArchiver.
     */
    convenience init?(dataUsingCIImage data: Data) {
        guard let ciImage = CIImage(data: data) else {
            self.init(data: data)
            return
        }
        let rep = NSCIImageRep(ciImage: ciImage)
        self.init(size: rep.size)
        addRepresentation(rep)
    }
}
