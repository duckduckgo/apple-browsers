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

@MainActor
final class SitePermissionsFaviconStore {
    let store: SitePermissionsStore

    private let cache: ImageCache
    private let isEnabled: () -> Bool
    private let fetchFavicon: (String, @escaping (UIImage?) -> Void) -> Void
    private let cachedFavicon: @MainActor (String) -> UIImage?
    private var storedSites = Set<SitePermissionKey>()
    private var viewModels = [SitePermissionKey: FaviconViewModel]()
    private var requests = [SitePermissionKey: UUID]()
    private var subscription: AnyCancellable?

    init(store: SitePermissionsStore,
         cache: ImageCache = Favicons.Constants.sitePermissionsCache,
         isEnabled: @escaping () -> Bool,
         cachedFavicon: @escaping @MainActor (String) -> UIImage? = SitePermissionsFaviconStore.cachedBrowsingFavicon,
         fetchFavicon: @escaping (String, @escaping (UIImage?) -> Void) -> Void) {
        self.store = store
        self.cache = cache
        self.isEnabled = isEnabled
        self.cachedFavicon = cachedFavicon
        self.fetchFavicon = fetchFavicon
        removeOrphanedFiles()
        refresh()
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

    func loadFavicon(for site: SitePermissionKey) {
        guard isEnabled(), store.storedSites.contains(site), requests[site] == nil else { return }
        if let image = retainedImage(for: site) {
            viewModel(for: site).image = image
            return
        }

        let requestID = UUID()
        requests[site] = requestID
        fetchFavicon(site.host) { [weak self] image in
            guard let self, self.requests[site] == requestID else { return }
            self.requests[site] = nil
            // A removal, Fire, or Undo can replace this record while the download is running.
            guard self.isEnabled(), self.store.storedSites.contains(site), let image else { return }
            self.retain(image, for: site)
            self.viewModel(for: site).image = image
        }
    }

    private func refresh() {
        let sites = store.storedSites
        for site in storedSites.subtracting(sites) {
            requests[site] = nil
            viewModels[site] = nil
            cache.removeImage(forKey: FaviconHasher.createHash(ofDomain: site.host))
        }
        if isEnabled() {
            for site in sites.subtracting(storedSites) {
                if let image = retainedImage(for: site) {
                    // Undo must queue the restored image after any pending disk removal.
                    retain(image, for: site)
                }
            }
        }
        storedSites = sites
    }

    private func retainedImage(for site: SitePermissionKey) -> UIImage? {
        let key = FaviconHasher.createHash(ofDomain: site.host)
        if let image = cache.retrieveImageInMemoryCache(forKey: key) { return image }
        if let data = try? cache.diskStorage.value(forKey: key), let image = UIImage(data: data) {
            return image
        }
        // Permission keys strip www.; the browsing and bookmark caches keep the visited host.
        guard let image = cachedFavicon(site.host) ?? cachedFavicon("www." + site.host) else { return nil }
        retain(image, for: site)
        return image
    }

    private func retain(_ image: UIImage, for site: SitePermissionKey) {
        cache.store(image, forKey: FaviconHasher.createHash(ofDomain: site.host),
                    options: KingfisherParsedOptionsInfo([.diskCacheExpiration(.never)]))
    }

    private func removeOrphanedFiles() {
        let keys = Set(store.storedSites.map { FaviconHasher.createHash(ofDomain: $0.host) })
        guard let files = try? FileManager.default.contentsOfDirectory(at: cache.diskStorage.directoryURL,
                                                                       includingPropertiesForKeys: nil) else { return }
        for file in files where !keys.contains(file.lastPathComponent) {
            cache.removeImage(forKey: file.lastPathComponent)
        }
    }

    private static func cachedBrowsingFavicon(for domain: String) -> UIImage? {
        for cacheType in [FaviconsCacheType.tabs, .fireproof] {
            let result = FaviconsHelper.loadFaviconSync(forDomain: domain, usingCache: cacheType, useFakeFavicon: false)
            if let image = result.image { return image }
        }
        return nil
    }
}
