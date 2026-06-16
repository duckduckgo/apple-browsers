//
//  FaviconImageCache.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation
import Combine
import Common
import FoundationExtensions
import BrowserServicesKit
import os.log

protocol FaviconImageCaching {

    init(faviconStoring: FaviconStoring)

    @MainActor
    var loaded: Bool { get }

    func load() async throws

    @MainActor
    func insert(_ favicons: [Favicon])

    @MainActor
    func get(faviconUrl: URL) -> Favicon?

    /// Awaits the off-main image decode on a cache miss and returns the favicon with its image (or a
    /// nil image when it can't be decoded). For callers that need the image now, e.g. the
    /// duck://favicon scheme handler.
    @MainActor
    func resolvedFavicon(faviconUrl: URL) async -> Favicon?

    @MainActor
    func getFavicons(with urls: some Sequence<URL>) -> [Favicon]?

    @MainActor
    func cleanOld(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager) async

    @MainActor
    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async -> Result<Void, Error>

    @MainActor
    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins logins: Set<String>,
                     exceptHistoryDomains history: Set<String>,
                     tld: TLD) async -> Result<Void, Error>

    /// Debug/admin: deletes the favicon image records with the given identifiers from memory + store and
    /// posts `.faviconCacheUpdated`. References pointing at a deleted favicon resolve to a cache miss and
    /// re-fetch on the next visit. No-op for an empty set.
    @MainActor
    func removeFavicons(withIdentifiers identifiers: Set<UUID>) async

    /// Debug/admin: deletes every cached favicon image record (memory + store) and posts `.faviconCacheUpdated`.
    @MainActor
    func removeAllFavicons() async
}

final class FaviconImageCache: FaviconImageCaching {

    /// Max cost is set to 32MB.
    ///
    /// At 64x64px, decoded RGBA should be 16kB per favicon and 32MB
    /// should be able to store >2000 favicons.
    private static let imageCacheTotalCostLimit = 32 * 1024 * 1024

    private let storing: FaviconStoring

    @MainActor
    private var entries = [URL: FaviconMetadata]()

    /// Bounded image cache.
    ///
    /// Cost is the image's real pixel byte size (see `pixelCost(of:)`),
    /// so `totalCostLimit` reflects actual resident memory rather than
    /// point-based dimensions, which on Retina displays undercount
    /// the backing bitmap by ~4×.
    private let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = imageCacheTotalCostLimit
        return cache
    }()

    // URLs whose image is currently being decoded off the main thread, used to
    // coalesce concurrent `get(faviconUrl:)` cache misses for the same favicon
    // (e.g. several UI consumers requesting the same icon at once).
    @MainActor
    private var inFlightImageLoads = Set<URL>()

    init(faviconStoring: FaviconStoring) {
        storing = faviconStoring
    }

    @MainActor
    private(set) var loaded = false

    func load() async throws {
        let metadata: [FaviconMetadata]
        do {
            metadata = try await storing.loadFaviconMetadata()
            Logger.favicons.debug("Favicon metadata loaded successfully (\(metadata.count) entries)")
        } catch {
            Logger.favicons.error("Loading of favicon metadata failed: \(error.localizedDescription)")
            throw error
        }

        await MainActor.run {
            for entry in metadata {
                entries[entry.url] = entry
            }
            loaded = true
        }
    }

    func insert(_ favicons: [Favicon]) {
        guard !favicons.isEmpty, loaded else {
            return
        }

        // Capture the metadata of any existing entries with the same URL so the
        // store can drop the prior rows after the new ones are saved.
        let oldMetadata = favicons.compactMap { entries[$0.url] }

        // Update metadata entries and image cache for the new favicons.
        for favicon in favicons {
            entries[favicon.url] = FaviconMetadata(favicon: favicon)
            cacheImage(favicon.image, for: favicon.url)
        }

        Task {
            do {
                await self.removeFaviconsFromStore(oldMetadata)
                try await self.storing.save(favicons)
                Logger.favicons.debug("Favicon saved successfully. URL: \(favicons.map(\.url.absoluteString).description)")
                await MainActor.run {
                    NotificationCenter.default.postFaviconCacheUpdated(
                        faviconURLs: Set(favicons.map(\.url)),
                        documentURLs: Set(favicons.map(\.documentUrl))
                    )
                }
            } catch {
                Logger.favicons.error("Saving of favicon failed: \(error.localizedDescription)")
            }
        }
    }

    func get(faviconUrl: URL) -> Favicon? {
        guard loaded, let metadata = entries[faviconUrl] else { return nil }

        // Hot path: image already in NSCache.
        let key = faviconUrl as NSURL
        if let cached = imageCache.object(forKey: key) {
            return Favicon(metadata: metadata, image: cached)
        }

        // Cold path: the image isn't decoded yet. Decoding a stored favicon means
        // unarchiving an NSImage off disk, so we must NOT do it synchronously on this
        // `@MainActor` call. Kick off the decode on the store's private-queue context
        // and return a metadata-only Favicon (nil image) now. When the decode finishes
        // we populate the NSCache and post `.faviconCacheUpdated`, which UI consumers
        // observe to re-resolve the favicon.
        loadImageOffMain(for: metadata)
        return Favicon(metadata: metadata, image: nil)
    }

    func resolvedFavicon(faviconUrl: URL) async -> Favicon? {
        guard loaded, let metadata = entries[faviconUrl] else { return nil }

        // Hot path: already decoded.
        if let cached = imageCache.object(forKey: faviconUrl as NSURL) {
            return Favicon(metadata: metadata, image: cached)
        }

        // Cold path: await the off-main decode, then cache + notify, and return the resolved favicon.
        let image: NSImage?
        do {
            image = try await storing.loadImage(for: metadata.identifier)
        } catch {
            Logger.favicons.error("Loading favicon image failed for \(metadata.url.absoluteString): \(error.localizedDescription)")
            image = nil
        }
        if let image {
            cacheImage(image, for: faviconUrl)
            NotificationCenter.default.postFaviconCacheUpdated(faviconURLs: [metadata.url], documentURLs: [metadata.documentUrl])
        }
        return Favicon(metadata: metadata, image: image)
    }

    @MainActor
    private func loadImageOffMain(for metadata: FaviconMetadata) {
        let faviconUrl = metadata.url
        // Coalesce duplicate in-flight loads for the same favicon URL.
        guard !inFlightImageLoads.contains(faviconUrl) else { return }
        inFlightImageLoads.insert(faviconUrl)

        Task { [storing] in
            let image: NSImage?
            do {
                image = try await storing.loadImage(for: metadata.identifier)
            } catch {
                Logger.favicons.error("Loading favicon image failed for \(metadata.url.absoluteString): \(error.localizedDescription)")
                image = nil
            }

            await MainActor.run {
                self.inFlightImageLoads.remove(faviconUrl)
                guard let image else { return }
                self.cacheImage(image, for: faviconUrl)
                // Tell UI consumers the image is now available so they re-resolve.
                NotificationCenter.default.postFaviconCacheUpdated(
                    faviconURLs: [metadata.url],
                    documentURLs: [metadata.documentUrl]
                )
            }
        }
    }

    func getFavicons(with urls: some Sequence<URL>) -> [Favicon]? {
        guard loaded else { return nil }
        return urls.compactMap { get(faviconUrl: $0) }
    }

    // MARK: - Clean

    func cleanOld(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager) async {
        let bookmarkedHosts = bookmarkManager.allHosts()
        await removeFavicons { metadata in
            guard let host = metadata.documentUrl.host else {
                return false
            }
            return metadata.dateCreated < Date.monthAgo &&
                !fireproofDomains.isFireproof(fireproofDomain: host) &&
                !bookmarkedHosts.contains(host)
        }
    }

    // MARK: - Burning

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async -> Result<Void, Error> {
        let bookmarkedHosts = bookmarkManager.allHosts()
        return await removeFavicons { metadata in
            guard let host = metadata.documentUrl.host else {
                return false
            }
            return !(fireproofDomains.isFireproof(fireproofDomain: host) ||
                     bookmarkedHosts.contains(host) ||
                     savedLogins.contains(host)
            )
        }
    }

    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins logins: Set<String>,
                     exceptHistoryDomains history: Set<String>,
                     tld: TLD) async -> Result<Void, Error> {
        let bookmarkedHosts = bookmarkManager.allHosts()
        return await removeFavicons { metadata in
            guard let host = metadata.documentUrl.host, let baseDomain = tld.eTLDplus1(host) else { return false }
            return baseDomains.contains(baseDomain)
                && !bookmarkedHosts.contains(host)
                && !logins.contains(host)
                && !history.contains(host)
        }
    }

    // MARK: - Debug / admin removal

    @MainActor
    func removeFavicons(withIdentifiers identifiers: Set<UUID>) async {
        guard !identifiers.isEmpty else { return }
        await deleteFaviconsAndNotify { identifiers.contains($0.identifier) }
    }

    @MainActor
    func removeAllFavicons() async {
        await deleteFaviconsAndNotify { _ in true }
    }

    /// Removes matching favicons from the in-memory metadata map and the decoded-image NSCache, deletes
    /// them from the store, and posts `.faviconCacheUpdated` so open UI re-resolves. Unlike the private
    /// `removeFavicons(filter:)` used by clean/burn, this always notifies.
    @MainActor
    private func deleteFaviconsAndNotify(filter isRemoved: (FaviconMetadata) -> Bool) async {
        let toRemove = entries.values.filter(isRemoved)
        guard !toRemove.isEmpty else { return }
        for metadata in toRemove {
            entries[metadata.url] = nil
            imageCache.removeObject(forKey: metadata.url as NSURL)
        }
        await removeFaviconsFromStore(Array(toRemove))
        NotificationCenter.default.postFaviconCacheUpdated(
            faviconURLs: Set(toRemove.map(\.url)),
            documentURLs: Set(toRemove.map(\.documentUrl))
        )
    }

    // MARK: - Private

    @discardableResult
    @MainActor
    private func removeFavicons(filter isRemoved: (FaviconMetadata) -> Bool) async -> Result<Void, Error> {
        let toRemove = entries.values.filter(isRemoved)
        for metadata in toRemove {
            entries[metadata.url] = nil
            imageCache.removeObject(forKey: metadata.url as NSURL)
        }
        return await removeFaviconsFromStore(Array(toRemove))
    }

    @discardableResult
    private func removeFaviconsFromStore(_ metadatas: [FaviconMetadata]) async -> Result<Void, Error> {
        guard !metadatas.isEmpty else { return .success(()) }

        // FaviconStoring.removeFavicons takes [Favicon] and only reads
        // `identifier` from each (see FaviconStore.removeFavicons). Wrap the
        // metadata in nil-image Favicons just for the delete call.
        let favicons = metadatas.map { $0.asFaviconWithoutImage() }
        do {
            try await storing.removeFavicons(favicons)
            Logger.favicons.debug("Favicons removed successfully.")
            return .success(())
        } catch {
            Logger.favicons.error("Removing of favicons failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    @MainActor
    private func cacheImage(_ image: NSImage?, for url: URL) {
        guard let image else { return }
        imageCache.setObject(image, forKey: url as NSURL, cost: Self.pixelCost(of: image))
    }

    /// Approximate resident memory of `image` in bytes, derived from the real
    /// pixel dimensions of its largest bitmap representation (RGBA, 4 bytes per
    /// pixel). `image.size` is in points, so on Retina displays the backing
    /// bitmap holds ~4× the pixels per point²; using points would undercount the
    /// cost and let the cache hold far more memory than `totalCostLimit` implies.
    static func pixelCost(of image: NSImage) -> Int {
        var maxCost = 0
        for rep in image.representations {
            let cost: Int
            if let bitmap = rep as? NSBitmapImageRep, bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 {
                // `bytesPerRow * pixelsHigh` is the most accurate, accounting for
                // row padding and the actual bytes-per-pixel of the bitmap.
                cost = bitmap.bytesPerRow * bitmap.pixelsHigh
            } else if rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                cost = rep.pixelsWide * rep.pixelsHigh * 4
            } else {
                // Vector/PDF reps report `NSImageRepMatchesDevice` (0) for pixel
                // dimensions; estimate from points scaled to a Retina backing.
                let scale = 2.0
                cost = Int(image.size.width * scale * image.size.height * scale * 4)
            }
            maxCost = max(maxCost, cost)
        }
        // Never report 0 for a non-empty image: an NSCache cost of 0 is treated
        // as free and the entry would never be evicted. Fall back to the
        // point-based size as a last resort.
        if maxCost == 0 {
            maxCost = Int(image.size.width * image.size.height * 4)
        }
        return max(maxCost, 1)
    }

}

// MARK: - Favicon ↔ FaviconMetadata bridges

private extension Favicon {

    init(metadata: FaviconMetadata, image: NSImage?) {
        self.init(identifier: metadata.identifier,
                  url: metadata.url,
                  image: image,
                  relation: metadata.relation,
                  documentUrl: metadata.documentUrl,
                  dateCreated: metadata.dateCreated)
    }

}

private extension FaviconMetadata {

    init(favicon: Favicon) {
        self.init(identifier: favicon.identifier,
                  url: favicon.url,
                  documentUrl: favicon.documentUrl,
                  dateCreated: favicon.dateCreated,
                  relation: favicon.relation)
    }

    func asFaviconWithoutImage() -> Favicon {
        Favicon(identifier: identifier,
                url: url,
                image: nil,
                relation: relation,
                documentUrl: documentUrl,
                dateCreated: dateCreated)
    }

}

// MARK: - Eager (legacy) favicon image cache

/**
 * Legacy eager favicon image cache, used when the `faviconLazyImageLoading` kill switch is disabled.
 *
 * Unlike `FaviconImageCache`, this loads every stored favicon — including its decoded image — into an
 * in-memory `[URL: Favicon]` dictionary at launch via `FaviconStoring.loadFavicons()`. This is the
 * behavior that shipped before lazy favicon loading was introduced; it is reachable as a remote
 * kill-switch fallback. It conforms to the same `FaviconImageCaching` protocol as the lazy cache.
 */
final class EagerFaviconImageCache: FaviconImageCaching {

    private let storing: FaviconStoring

    @MainActor
    private var entries = [URL: Favicon]()

    init(faviconStoring: FaviconStoring) {
        storing = faviconStoring
    }

    @MainActor
    private(set) var loaded = false

    func load() async throws {
        let favicons: [Favicon]
        do {
            favicons = try await storing.loadFavicons()
            Logger.favicons.debug("Favicons loaded successfully")
        } catch {
            Logger.favicons.error("Loading of favicons failed: \(error.localizedDescription)")
            throw error
        }

        await MainActor.run {
            for favicon in favicons {
                entries[favicon.url] = favicon
            }
            loaded = true
        }
    }

    func insert(_ favicons: [Favicon]) {
        guard !favicons.isEmpty, loaded else {
            return
        }

        // Remove existing favicon with the same URL
        let oldFavicons = favicons.compactMap { entries[$0.url] }

        // Save the new ones
        for favicon in favicons {
            entries[favicon.url] = favicon
        }

        Task {
            do {
                await self.removeFaviconsFromStore(oldFavicons)
                try await self.storing.save(favicons)
                Logger.favicons.debug("Favicon saved successfully. URL: \(favicons.map(\.url.absoluteString).description)")
                await MainActor.run {
                    NotificationCenter.default.postFaviconCacheUpdated(
                        faviconURLs: Set(favicons.map(\.url)),
                        documentURLs: Set(favicons.map(\.documentUrl))
                    )
                }
            } catch {
                Logger.favicons.error("Saving of favicon failed: \(error.localizedDescription)")
            }
        }
    }

    func get(faviconUrl: URL) -> Favicon? {
        guard loaded else { return nil }

        return entries[faviconUrl]
    }

    func resolvedFavicon(faviconUrl: URL) async -> Favicon? {
        // The eager cache already holds decoded images, so there's nothing to await.
        guard loaded else { return nil }
        return entries[faviconUrl]
    }

    func getFavicons(with urls: some Sequence<URL>) -> [Favicon]? {
        guard loaded else { return nil }

        return urls.compactMap { faviconUrl in entries[faviconUrl] }
    }

    // MARK: - Clean

    func cleanOld(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager) async {
        let bookmarkedHosts = bookmarkManager.allHosts()
        await removeFavicons { favicon in
            guard let host = favicon.documentUrl.host else {
                return false
            }
            return favicon.dateCreated < Date.monthAgo &&
                !fireproofDomains.isFireproof(fireproofDomain: host) &&
                !bookmarkedHosts.contains(host)
        }
    }

    // MARK: - Burning

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async -> Result<Void, Error> {
        let bookmarkedHosts = bookmarkManager.allHosts()
        return await removeFavicons { favicon in
            guard let host = favicon.documentUrl.host else {
                return false
            }
            return !(fireproofDomains.isFireproof(fireproofDomain: host) ||
                     bookmarkedHosts.contains(host) ||
                     savedLogins.contains(host)
            )
        }
    }

    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins logins: Set<String>,
                     exceptHistoryDomains history: Set<String>,
                     tld: TLD) async -> Result<Void, Error> {
        let bookmarkedHosts = bookmarkManager.allHosts()
        return await removeFavicons { favicon in
            guard let host = favicon.documentUrl.host, let baseDomain = tld.eTLDplus1(host) else { return false }
            return baseDomains.contains(baseDomain)
                && !bookmarkedHosts.contains(host)
                && !logins.contains(host)
                && !history.contains(host)
        }
    }

    // MARK: - Debug / admin removal

    @MainActor
    func removeFavicons(withIdentifiers identifiers: Set<UUID>) async {
        guard !identifiers.isEmpty else { return }
        await deleteFaviconsAndNotify { identifiers.contains($0.identifier) }
    }

    @MainActor
    func removeAllFavicons() async {
        await deleteFaviconsAndNotify { _ in true }
    }

    @MainActor
    private func deleteFaviconsAndNotify(filter isRemoved: (Favicon) -> Bool) async {
        let toRemove = entries.values.filter(isRemoved)
        guard !toRemove.isEmpty else { return }
        toRemove.forEach { entries[$0.url] = nil }
        await removeFaviconsFromStore(toRemove)
        NotificationCenter.default.postFaviconCacheUpdated(
            faviconURLs: Set(toRemove.map(\.url)),
            documentURLs: Set(toRemove.map(\.documentUrl))
        )
    }

    // MARK: - Private

    @discardableResult
    @MainActor
    private func removeFavicons(filter isRemoved: (Favicon) -> Bool) async -> Result<Void, Error> {
        let faviconsToRemove = entries.values.filter(isRemoved)
        faviconsToRemove.forEach { entries[$0.url] = nil }

        return await removeFaviconsFromStore(faviconsToRemove)
    }

    private func removeFaviconsFromStore(_ favicons: [Favicon]) async -> Result<Void, Error> {
        guard !favicons.isEmpty else { return .success(()) }

        do {
            try await storing.removeFavicons(favicons)
            Logger.favicons.debug("Favicons removed successfully.")
            return .success(())
        } catch {
            Logger.favicons.error("Removing of favicons failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}
