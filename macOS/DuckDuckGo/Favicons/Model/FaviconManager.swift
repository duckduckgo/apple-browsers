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
import BrowserServicesKit
import FeatureFlags
import Cocoa
import Combine
import Common
import FoundationExtensions
import CoreImage
import History
import os.log
import Persistence
import PrivacyConfig
import UserScript
import WebKit

protocol FaviconManagement: AnyObject {

    @MainActor
    var isCacheLoaded: Bool { get }

    var faviconsLoadedPublisher: Published<Bool>.Publisher { get }

    @MainActor
    func handleFaviconLinks(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL, webView: WKWebView?) async -> Favicon?

    @MainActor
    func handleFaviconsByDocumentUrl(_ faviconsByDocumentUrl: [URL: [Favicon]]) async

    @MainActor
    func getCachedFaviconURL(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> URL?

    @MainActor
    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?

    /// Awaits the favicon image decode (used by the duck://favicon scheme handler so it returns the
    /// image once decoded instead of a cache-missed 404).
    @MainActor
    func resolvedCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) async -> Favicon?

    /// Awaits the favicon image decode for a host-keyed lookup (used by `LoginFaviconView` so it shows
    /// the image once decoded instead of relying on a cache-update notification).
    @MainActor
    func resolvedCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory) async -> Favicon?

    @MainActor
    func getCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?

    @MainActor
    func getCachedFavicon(forDomainOrAnySubdomain domain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?

    @MainActor
    func burn(except: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async -> Result<Void, Error>

    @MainActor
    func burnDomains(_ domains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins: Set<String>,
                     exceptExistingHistory history: BrowsingHistory,
                     tld: TLD) async -> Result<Void, Error>
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

    @MainActor
    func getCachedFaviconSafeForRendering(for host: String, sizeCategory: Favicon.SizeCategory) -> Favicon? {
        guard shouldRenderFavicon else {
            return nil
        }

        return getCachedFavicon(for: host, sizeCategory: sizeCategory)
    }

    @MainActor
    func resolvedCachedFaviconSafeForRendering(for host: String, sizeCategory: Favicon.SizeCategory) async -> Favicon? {
        guard shouldRenderFavicon else {
            return nil
        }

        return await resolvedCachedFavicon(for: host, sizeCategory: sizeCategory)
    }

    @MainActor
    func getCachedFavicon(forUrlOrAnySubdomain documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        if let favicon = getCachedFavicon(for: documentUrl, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller) {
            return favicon
        }

        if let domain = documentUrl.host?.dropSubdomain(), let favicon = getCachedFavicon(forDomainOrAnySubdomain: domain, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller) {
            return favicon
        }

        return nil
    }

    @MainActor
    private var shouldRenderFavicon: Bool {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion

        // Workaround for favicon rendering crashes on Ventura 13.7.8 and newer 13.x patches.
        switch (osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion) {
        case let (13, minor, _) where minor > 7:
            return false
        case let (13, 7, patch) where patch >= 8:
            return false
        default:
            return true
        }
    }
}

/// Describes a favicon's pixel size and whether it's an SVG — the inputs to `FaviconManager.faviconsToKeep`.
protocol FaviconSizeRepresentable {
    var longestSide: CGFloat { get }
    var isSVG: Bool { get }
}

final class FaviconManager: FaviconManagement {

    enum CacheType {
        case standard(_ database: CoreDataDatabase)
        case inMemory
    }

    private(set) var store: FaviconStoring

    private let bookmarkManager: BookmarkManager
    private let faviconDownloader: FaviconDownloader
    private let featureFlagger: FeatureFlagger

    @Published private var faviconsLoaded = false
    var faviconsLoadedPublisher: Published<Bool>.Publisher { $faviconsLoaded }

    var isCacheLoaded: Bool {
        imageCache.loaded && referenceCache.loaded
    }

    init(
        cacheType: CacheType,
        bookmarkManager: BookmarkManager,
        fireproofDomains: FireproofDomains,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        featureFlagger: FeatureFlagger,
        imageCache: ((FaviconStoring) -> FaviconImageCaching)? = nil,
        referenceCache: ((FaviconStoring) -> FaviconReferenceCaching)? = nil
    ) {
        switch cacheType {
        case .standard(let database):
            store = FaviconStore(database: database)
        case .inMemory:
            store = FaviconNullStore()
        }
        self.bookmarkManager = bookmarkManager
        self.faviconDownloader = FaviconDownloader(privacyConfigurationManager: privacyConfigurationManager)
        self.featureFlagger = featureFlagger
        if let imageCache {
            self.imageCache = imageCache(store)
        } else if featureFlagger.isFeatureOn(.faviconLazyImageLoading) {
            self.imageCache = FaviconImageCache(faviconStoring: store)
        } else {
            self.imageCache = EagerFaviconImageCache(faviconStoring: store)
        }
        self.referenceCache = referenceCache?(store) ?? FaviconReferenceCache(faviconStoring: store)

        Task {
            try? await loadFavicons(fireproofDomains)
        }
    }

    private func loadFavicons(_ fireproofDomains: FireproofDomains) async throws {
        try await imageCache.load()
        await imageCache.cleanOld(except: fireproofDomains, bookmarkManager: bookmarkManager)
        try await referenceCache.load()
        await referenceCache.cleanOld(except: fireproofDomains, bookmarkManager: bookmarkManager)
        faviconsLoaded = true
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

    func handleFaviconLinks(_ faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL, webView: WKWebView?) async -> Favicon? {
        await awaitFaviconsLoaded()
        guard !Task.isCancelled else { return nil }

        // If we have links from the page, try those first
        // Fetch favicons if needed
        var faviconLinksToFetch = await filteringAlreadyFetchedFaviconLinks(from: faviconLinks)
        var newFavicons = await fetchFavicons(faviconLinks: faviconLinksToFetch, documentUrl: documentUrl, webView: webView)
        if let favicon = await cacheFavicons(newFavicons, faviconURLs: faviconLinks.lazy.map(\.href), for: documentUrl) {
            return favicon
        }
        guard !Task.isCancelled else { return nil }

        // If main links failed or were empty, try fallback
        let fallbackLinks = fallbackFaviconLinks(for: documentUrl)
        faviconLinksToFetch = await filteringAlreadyFetchedFaviconLinks(from: fallbackLinks)
        newFavicons = await fetchFavicons(faviconLinks: faviconLinksToFetch, documentUrl: documentUrl, webView: webView)
        return await cacheFavicons(newFavicons, faviconURLs: fallbackLinks.lazy.map(\.href), for: documentUrl)
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
        let cachedFaviconUrls = cachedFavicons.map { $0.url }
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

    @MainActor
    func resolvedCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) async -> Favicon? {
        await awaitFaviconsLoaded()
        guard let faviconURL = getCachedFaviconURL(for: documentUrl, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller) else {
            return nil
        }
        return await imageCache.resolvedFavicon(faviconUrl: faviconURL)
    }

    @MainActor
    func resolvedCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory) async -> Favicon? {
        await awaitFaviconsLoaded()
        guard let faviconURL = referenceCache.getFaviconUrl(for: host, sizeCategory: sizeCategory) else {
            return nil
        }
        return await imageCache.resolvedFavicon(faviconUrl: faviconURL)
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

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String> = []) async -> Result<Void, Error> {
        await referenceCache.burn(except: fireproofDomains, bookmarkManager: bookmarkManager, savedLogins: savedLogins)
        return await imageCache.burn(except: fireproofDomains, bookmarkManager: bookmarkManager, savedLogins: savedLogins)
    }

    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins: Set<String> = [],
                     exceptExistingHistory history: BrowsingHistory,
                     tld: TLD) async -> Result<Void, Error> {
        let existingHistoryDomains = Set(history.compactMap { $0.url.host })

        await referenceCache.burnDomains(baseDomains, exceptBookmarks: bookmarkManager,
                                         exceptSavedLogins: exceptSavedLogins,
                                         exceptHistoryDomains: existingHistoryDomains,
                                         tld: tld)
        return await imageCache.burnDomains(baseDomains,
                                            exceptBookmarks: bookmarkManager,
                                            exceptSavedLogins: exceptSavedLogins,
                                            exceptHistoryDomains: existingHistoryDomains,
                                            tld: tld)
    }

    // MARK: - Private

    private func fallbackFaviconLinks(for documentUrl: URL) -> [FaviconUserScript.FaviconLink] {
        guard let root = documentUrl.root else { return [] }
        var result = [FaviconUserScript.FaviconLink]()
        if [.https, .http].contains(documentUrl.navigationalScheme) {
            result.append(FaviconUserScript.FaviconLink(href: root.appending("favicon.ico"), rel: "favicon.ico"))
        }
        if documentUrl.navigationalScheme == .http, let upgradedRoot = root.toHttps() {
            result.append(FaviconUserScript.FaviconLink(href: upgradedRoot.appending("favicon.ico"), rel: "favicon.ico"))
        }
        return result
    }

    private func filteringAlreadyFetchedFaviconLinks(from faviconLinks: [FaviconUserScript.FaviconLink]) async -> [FaviconUserScript.FaviconLink] {
        guard !faviconLinks.isEmpty else { return [] }

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

    private func fetchFavicons(faviconLinks: [FaviconUserScript.FaviconLink], documentUrl: URL, webView: WKWebView?) async -> [Favicon] {
        guard !faviconLinks.isEmpty else { return [] }

        // Download and decode every favicon at full resolution first. We need each favicon's original
        // size to decide which ones to keep — if we downscaled during the download (capping every favicon
        // at `maxStoredFaviconPixelSize`) we could no longer tell the redundant large ones apart.
        let fetched: [FetchedFavicon] = await withTaskGroup(of: FetchedFavicon?.self) { [faviconDownloader] group in
            for faviconLink in faviconLinks {
                let faviconUrl = faviconLink.href
                group.addTask {
                    do {
                        try Task.checkCancellation()

                        let data = try await faviconDownloader.download(from: faviconUrl, using: webView)

                        try Task.checkCancellation()

                        // Validate that we got actual image data
                        guard !data.isEmpty else {
                            throw URLError(.zeroByteResource, userInfo: [NSURLErrorKey: faviconUrl])
                        }
                        guard let image = NSImage(dataUsingCIImage: data, maxPixelSize: nil) else {
                            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: faviconUrl])
                        }

                        return FetchedFavicon(link: faviconLink, data: data, image: image)
                    } catch {
                        Logger.favicons.error("Error downloading Favicon from \(faviconUrl.shortDescription): \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            var result = [FetchedFavicon]()
            for await fetchedFavicon in group {
                guard !Task.isCancelled else {
                    return []
                }
                if let fetchedFavicon {
                    result.append(fetchedFavicon)
                }
            }

            return result
        }

        // With the storing improvements off, follow the pre-existing path: store every fetched favicon at
        // its original resolution.
        guard featureFlagger.isFeatureOn(.faviconStoringImprovements) else {
            return fetched.map { fetchedFavicon in
                Favicon(identifier: UUID(),
                        url: fetchedFavicon.link.href,
                        image: fetchedFavicon.image,
                        relationString: fetchedFavicon.link.rel,
                        documentUrl: documentUrl,
                        dateCreated: Date())
            }
        }

        // Storing improvements on: the browser never displays a favicon larger than `maxStoredFaviconPixelSize`
        // (64px = 32@2x), so keep only the favicons we need (dropping redundant larger ones and unneeded SVGs)
        // and downscale the single kept larger favicon to the max stored size.
        return Self.faviconsToKeep(fetched, maxStoredSize: NSImage.maxStoredFaviconPixelSize).map { fetchedFavicon -> Favicon in
            let image: NSImage
            if fetchedFavicon.longestSide > NSImage.maxStoredFaviconPixelSize,
               let downscaled = NSImage(dataUsingCIImage: fetchedFavicon.data, maxPixelSize: NSImage.maxStoredFaviconPixelSize) {
                image = downscaled
            } else {
                image = fetchedFavicon.image
            }
            return Favicon(identifier: UUID(),
                           url: fetchedFavicon.link.href,
                           image: image,
                           relationString: fetchedFavicon.link.rel,
                           documentUrl: documentUrl,
                           dateCreated: Date())
        }
    }

    /// A favicon downloaded at full resolution, retained while we decide which favicons to keep.
    private struct FetchedFavicon: FaviconSizeRepresentable {
        let link: FaviconUserScript.FaviconLink
        let data: Data
        let image: NSImage

        var longestSide: CGFloat { max(image.size.width, image.size.height) }

        var isSVG: Bool {
            if let type = link.type?.lowercased(), type.contains("svg") {
                return true
            }
            return link.href.pathExtension.lowercased() == "svg"
        }
    }

    /**
     * Returns the favicons to keep, in their original order, given each favicon's longest-side pixel size
     * and whether it's an SVG.
     *
     * The browser never displays a favicon larger than `maxStoredSize` (64px = 32@2x), so larger favicons
     * are redundant. The rules:
     * - every raster favicon up to and including `maxStoredSize` is kept;
     * - if a raster favicon exactly `maxStoredSize` exists, all larger favicons are dropped;
     * - otherwise the smallest raster favicon size larger than `maxStoredSize` is kept;
     * - an SVG is kept only when no raster favicon reaches `maxStoredSize` (i.e. every raster is smaller),
     *   since otherwise a raster already covers the largest size the browser displays;
     * - duplicate raster favicons of the same pixel size are de-duplicated (only the first is kept).
     */
    static func faviconsToKeep<F: FaviconSizeRepresentable>(_ favicons: [F], maxStoredSize: CGFloat) -> [F] {
        let hasExactMax = favicons.contains { !$0.isSVG && $0.longestSide == maxStoredSize }
        // An SVG is only useful when no raster favicon already covers the largest displayed size, i.e. when
        // every raster favicon is smaller than the max.
        let hasRasterAtLeastMax = favicons.contains { !$0.isSVG && $0.longestSide >= maxStoredSize }

        // When there's no exact-max raster favicon, the larger favicon we keep is the smallest larger size.
        let smallestLargerSize: CGFloat? = hasExactMax ? nil : favicons.lazy
            .filter { !$0.isSVG && $0.longestSide > maxStoredSize }
            .map(\.longestSide)
            .min()

        // Keep the eligible favicons, de-duplicating raster favicons of the same pixel size (keep the first).
        var keptRasterSizes = Set<CGFloat>()
        return favicons.filter { favicon in
            if favicon.isSVG {
                return !hasRasterAtLeastMax
            }
            // Larger-than-max rasters are eligible only at the smallest larger size (and only when there's no
            // exact-max favicon, in which case `smallestLargerSize` is nil and they're all dropped).
            let isEligible = favicon.longestSide <= maxStoredSize || favicon.longestSide == smallestLargerSize
            guard isEligible else { return false }
            return keptRasterSizes.insert(favicon.longestSide).inserted
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

extension NSImage {

    /**
     * The maximum pixel size (longest side) at which freshly downloaded favicons are stored and cached.
     *
     * The largest size the app ever *displays* a favicon is the New Tab Page favorites tile, which is
     * 32 pt; at 2x Retina that is 64 device px (the NTP itself requests favicons at 64px).
     * Anything larger is wasted memory and disk space, so downloaded favicons are downscaled to this cap
     * before being stored. Bump this if a larger favicon display surface is ever introduced.
     */
    static let maxStoredFaviconPixelSize: CGFloat = 64

    /**
     * This function attempts to initialize `NSImage` from `CIImage`.
     *
     * This helps to preserve transparency on some PNG images, and fixes
     * storing `NSImage` initialized with `ico` files in NSKeyedArchiver.
     *
     * When `maxPixelSize` is non-nil, freshly decoded images are downscaled to that cap (longest side,
     * aspect ratio preserved) so that both the in-memory image and the archived blob stay small; images
     * already at or below the cap are left untouched (downscale only, never upscale). When `maxPixelSize`
     * is `nil` (downscaling disabled), the image is stored at its original resolution.
     */
    convenience init?(dataUsingCIImage data: Data, maxPixelSize: CGFloat?) {
        guard let ciImage = CIImage(data: data) else {
            self.init(data: data)
            return
        }

        let rep = NSImage.bitmapRep(from: ciImage, maxPixelSize: maxPixelSize)
        self.init(size: rep.size)
        addRepresentation(rep)
    }

    /**
     * Renders the given `CIImage` into a bitmap-backed image representation. When `maxPixelSize` is
     * non-nil, the pixel dimensions are capped at that value on the longest side (aspect ratio preserved,
     * downscale only); when `nil`, the image is rendered at its original resolution.
     *
     * The result is always a concrete `NSBitmapImageRep` (not a lazy `NSCIImageRep`), so the backing bitmap
     * and the archived blob are concrete. Its `size` (in points) equals its pixel dimensions, which keeps
     * `Favicon.SizeCategory` classification (driven by `image.size`) consistent with the actual pixels.
     */
    private static func bitmapRep(from ciImage: CIImage, maxPixelSize: CGFloat?) -> NSImageRep {
        let extent = ciImage.extent
        let longestSide = max(extent.width, extent.height)

        // Downscale only when a cap is provided and the image exceeds it; never upscale.
        let scaledImage: CIImage
        if let maxPixelSize, longestSide > maxPixelSize, longestSide.isFinite, longestSide > 0 {
            let scaleFactor = maxPixelSize / longestSide
            // High-quality (Lanczos) downscaling keeps small favicons crisp; fall back to an affine
            // transform if the filter is unavailable for the input.
            let lanczos = CIFilter(name: "CILanczosScaleTransform", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputScaleKey: scaleFactor,
                kCIInputAspectRatioKey: 1.0
            ])
            scaledImage = lanczos?.outputImage ?? ciImage.scaled(by: scaleFactor)
        } else {
            scaledImage = ciImage
        }

        // Render to a concrete CGImage with high-quality interpolation, then wrap in a bitmap rep.
        let context = CIContext(options: [.highQualityDownsample: true])
        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            // Keep points == pixels (1:1) so SizeCategory, which reads `image.size`, reflects real pixels.
            bitmapRep.size = NSSize(width: cgImage.width, height: cgImage.height)
            return bitmapRep
        }

        // Fallback: if rendering fails for some reason, fall back to the original CIImage-backed rep.
        return NSCIImageRep(ciImage: scaledImage)
    }
}

extension NSImage {
    /// Returns a `data:image/png;base64,...` string for this image, or nil if encoding fails.
    var base64PNGDataURL: String? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }
}

// MARK: - Favicon Browser (debug) support

/**
 * Read/delete access to the favicon store used by the debug-only Favicon Browser page (`duck://favicons`).
 *
 * Only `FaviconManager` conforms; `DuckURLSchemeHandler` downcasts its `FaviconManagement` to this
 * protocol when serving the page, so the debug surface stays off the main `FaviconManagement` protocol
 * (and its mocks). All access goes through the in-app favicon stack, which holds the decryption key, so
 * the encrypted URL/image columns are handled transparently.
 */
@MainActor
protocol FaviconManagementDebugging: AnyObject {

    /// Metadata for every stored favicon image record (no image decode), ordered oldest-first.
    func allFaviconsMetadata() async -> [FaviconMetadata]

    /// The decoded image for a single favicon record, by its identifier, or nil if missing/undecodable.
    func faviconImage(withIdentifier identifier: UUID) async -> NSImage?

    /// Deletes the favicon image records with the given identifiers (memory + store).
    func deleteFavicons(withIdentifiers identifiers: Set<UUID>) async

    /// Deletes every favicon image record and every favicon reference (full reset).
    func deleteAllFavicons() async
}

extension FaviconManager: FaviconManagementDebugging {

    @MainActor
    func allFaviconsMetadata() async -> [FaviconMetadata] {
        (try? await store.loadFaviconMetadata()) ?? []
    }

    @MainActor
    func faviconImage(withIdentifier identifier: UUID) async -> NSImage? {
        try? await store.loadImage(for: identifier)
    }

    @MainActor
    func deleteFavicons(withIdentifiers identifiers: Set<UUID>) async {
        await imageCache.removeFavicons(withIdentifiers: identifiers)
    }

    @MainActor
    func deleteAllFavicons() async {
        await imageCache.removeAllFavicons()
        await referenceCache.removeAllReferences()
    }

    /// Debug: clears the in-memory decoded-image cache without deleting any stored favicons. Only the
    /// lazy `FaviconImageCache` keeps a separate in-memory image cache, so this is a no-op on the eager
    /// (non-lazy) path.
    @MainActor
    func clearInMemoryFaviconCache() {
        (imageCache as? FaviconImageCache)?.clearInMemoryCache()
    }
}
