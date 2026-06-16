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
}

final class FaviconImageCache: FaviconImageCaching {

    private static let imageCacheTotalCostLimit = 32 * 1024 * 1024

    private let storing: FaviconStoring

    @MainActor
    private var entries = [URL: FaviconMetadata]()

    // Bounded image cache. Cost is approximated as RGBA size-units in points
    // (so retina images undercount by ~4×); NSCache only requires the cost to
    // be proportional, not byte-accurate, and computing real PNG bytes would
    // mean re-encoding on every insert.
    private let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.totalCostLimit = imageCacheTotalCostLimit
        return cache
    }()

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
                    NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
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

        // Cold path: synchronous single-row fetch from the store. Per
        // FaviconStore.loadImage, this is a `performAndWait` against the
        // private-queue context — typically ~1 ms; under simultaneous write
        // load it can briefly stall main. Documented trade-off.
        let image: NSImage?
        do {
            image = try storing.loadImage(for: metadata.identifier)
        } catch {
            Logger.favicons.error("Loading favicon image failed for \(metadata.url.absoluteString): \(error.localizedDescription)")
            image = nil
        }
        cacheImage(image, for: faviconUrl)
        return Favicon(metadata: metadata, image: image)
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

    // MARK: - Private

    @MainActor
    private func removeFavicons(filter isRemoved: (FaviconMetadata) -> Bool) async -> Result<Void, Error> {
        let toRemove = entries.values.filter(isRemoved)
        for metadata in toRemove {
            entries[metadata.url] = nil
            imageCache.removeObject(forKey: metadata.url as NSURL)
        }
        return await removeFaviconsFromStore(Array(toRemove))
    }

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
        let cost = Int(image.size.width * image.size.height * 4)
        imageCache.setObject(image, forKey: url as NSURL, cost: cost)
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
