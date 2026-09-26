//
//  SitePermissionsFaviconStore.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Core
import Kingfisher
import SitePermissions
import UIKit

/// Keeps a favicon for each site with a saved permission record, for as long as the record exists.
/// Images come only from the app's local favicon caches; this type never downloads.
@MainActor
final class SitePermissionsFaviconStore {
    private let store: SitePermissionsStore
    private let cache: ImageCache
    private let isEnabled: () -> Bool
    private let cachedFavicon: @MainActor (String) -> UIImage?
    private var storedSites = Set<SitePermissionKey>()
    private var viewModels = [SitePermissionKey: FaviconViewModel]()
    private var subscription: AnyCancellable?

    init(store: SitePermissionsStore,
         cache: ImageCache = Favicons.Constants.sitePermissionsCache,
         isEnabled: @escaping () -> Bool,
         cachedFavicon: @escaping @MainActor (String) -> UIImage? = SitePermissionsFaviconStore.cachedBrowsingFavicon) {
        self.store = store
        self.cache = cache
        self.isEnabled = isEnabled
        self.cachedFavicon = cachedFavicon
        storedSites = store.storedSites
        synchronizeDiskCache()
        subscription = store.changesPublisher.sink { [weak self] in self?.refresh() }
    }

    func viewModel(for site: SitePermissionKey) -> FaviconViewModel {
        if let viewModel = viewModels[site] { return viewModel }
        let viewModel = FaviconViewModel(domain: site.host)
        if isEnabled(), store.storedSites.contains(site), let image = retainedImage(for: site) {
            viewModel.image = image
        }
        viewModels[site] = viewModel
        return viewModel
    }

    /// Picks up a favicon that reached the browsing caches after the row was created.
    func loadFavicon(for site: SitePermissionKey) {
        guard isEnabled(), store.storedSites.contains(site), let image = retainedImage(for: site) else { return }
        viewModel(for: site).image = image
    }

    private func refresh() {
        let sites = store.storedSites
        for site in storedSites.subtracting(sites) {
            viewModels[site] = nil
            cache.removeImage(forKey: cacheKey(for: site))
        }
        if isEnabled() {
            for site in sites.subtracting(storedSites) {
                // Undo can re-add a site before its queued disk removal runs; storing again keeps the image.
                if let image = storedImage(for: site) ?? browsingImage(for: site) {
                    retain(image, for: site)
                }
            }
        }
        storedSites = sites
    }

    private func retainedImage(for site: SitePermissionKey) -> UIImage? {
        if let image = storedImage(for: site) { return image }
        guard let image = browsingImage(for: site) else { return nil }
        retain(image, for: site)
        return image
    }

    private func storedImage(for site: SitePermissionKey) -> UIImage? {
        let key = cacheKey(for: site)
        if let image = cache.retrieveImageInMemoryCache(forKey: key) { return image }
        guard let data = try? cache.diskStorage.value(forKey: key) else { return nil }
        return UIImage(data: data)
    }

    private func browsingImage(for site: SitePermissionKey) -> UIImage? {
        // Permission keys strip www.; the browsing and bookmark caches keep the visited host.
        cachedFavicon(site.host) ?? cachedFavicon("www." + site.host)
    }

    private func retain(_ image: UIImage, for site: SitePermissionKey) {
        cache.store(image, forKey: cacheKey(for: site),
                    options: KingfisherParsedOptionsInfo([.diskCacheExpiration(.never)]))
    }

    /// Runs at launch, so it reads only the directory listing: images without a record are removed,
    /// and a site without an image retains one from the browsing caches if they still have it.
    private func synchronizeDiskCache() {
        let files = (try? FileManager.default.contentsOfDirectory(at: cache.diskStorage.directoryURL,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let cachedKeys = Set(files.map(\.lastPathComponent))
        let sitesByKey = Dictionary(storedSites.map { (cacheKey(for: $0), $0) }, uniquingKeysWith: { site, _ in site })
        for key in cachedKeys where sitesByKey[key] == nil {
            cache.removeImage(forKey: key)
        }
        guard isEnabled() else { return }
        for (key, site) in sitesByKey where !cachedKeys.contains(key) {
            if let image = browsingImage(for: site) {
                retain(image, for: site)
            }
        }
    }

    private func cacheKey(for site: SitePermissionKey) -> String {
        FaviconHasher.createHash(ofDomain: site.host)
    }

    private static func cachedBrowsingFavicon(for domain: String) -> UIImage? {
        for cacheType in [FaviconsCacheType.tabs, .fireproof] {
            let result = FaviconsHelper.loadFaviconSync(forDomain: domain, usingCache: cacheType, useFakeFavicon: false)
            if let image = result.image { return image }
        }
        return nil
    }
}
