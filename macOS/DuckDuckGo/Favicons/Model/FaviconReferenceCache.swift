//
//  FaviconReferenceCache.swift
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

import Foundation
import Combine
import Common
import FoundationExtensions
import BrowserServicesKit
import os.log

protocol FaviconReferenceCaching {

    init(faviconStoring: FaviconStoring)

    // References to favicon URLs for whole domains
    @MainActor
    var hostReferences: [String: FaviconHostReference] { get }

    // References to favicon URLs for special URLs
    @MainActor
    var urlReferences: [URL: FaviconUrlReference] { get }

    @MainActor
    var loaded: Bool { get }

    @MainActor
    func load() async throws

    @MainActor
    func insert(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL)

    @MainActor
    func getFaviconUrl(for documentURL: URL, sizeCategory: Favicon.SizeCategory) -> URL?
    @MainActor
    func getFaviconUrl(for host: String, sizeCategory: Favicon.SizeCategory) -> URL?

    @MainActor
    func cleanOld(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager) async
    @MainActor
    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async
    @MainActor
    func burnDomains(_ baseDomains: Set<String>, exceptBookmarks bookmarkManager: BookmarkManager, exceptSavedLogins logins: Set<String>, exceptHistoryDomains history: Set<String>, tld: TLD) async

    /// Debug/admin: removes every host and URL favicon reference from memory + store.
    @MainActor
    func removeAllReferences() async
}

final class FaviconReferenceCache: FaviconReferenceCaching {

    private let storing: FaviconStoring

    // References to favicon URLs for whole domains
    private(set) var hostReferences = [String: FaviconHostReference]()

    // References to favicon URLs for special URLs
    private(set) var urlReferences = [URL: FaviconUrlReference]()

    init(faviconStoring: FaviconStoring) {
        storing = faviconStoring
    }

    private(set) var loaded = false

    func load() async throws {
        do {
            let (hostReferences, urlReferences) = try await storing.loadFaviconReferences()

            // Drop references with no favicon URL. They carry no information - a lookup
            // returns `nil` whether such a reference exists or not. An empty URL reference
            // used to shadow a good host reference for the same host, which was a bug.
            let (emptyHostReferences, validHostReferences) = hostReferences.extractEmpty()
            let (emptyUrlReferences, validUrlReferences) = urlReferences.extractEmpty()

            for reference in validHostReferences {
                self.hostReferences[reference.host] = reference
            }
            for reference in validUrlReferences {
                self.urlReferences[reference.documentUrl] = reference
            }
            loaded = true

            Logger.favicons.debug("References loaded successfully")

            if !emptyHostReferences.isEmpty || !emptyUrlReferences.isEmpty {
                Logger.favicons.debug("Discarding \(emptyHostReferences.count) empty host and \(emptyUrlReferences.count) empty URL references")
                Task.detached {
                    await self.removeHostReferencesFromStore(emptyHostReferences)
                    await self.removeUrlReferencesFromStore(emptyUrlReferences)
                }
            }

            NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
        } catch {
            Logger.favicons.error("Loading of references failed: \(error.localizedDescription)")
            throw error
        }
    }

    func insert(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL) {
        guard loaded else { return }

        // Never replace a usable reference with an empty one. A favicon fetch that returns nothing
        // (network error, 404, cancelled navigation) reaches this point with both URLs `nil`; writing
        // that would destroy the favicon reference the site already has, and the favicon would stay
        // missing until the next successful fetch.
        // This also means that we wouldn't immediately clear a favicon on a website that removed a favicon,
        // but it's a reasonable trade-off considering the breakage caused by otherwise displaying incorrect favicons.
        if faviconUrls.smallFaviconUrl == nil, faviconUrls.mediumFaviconUrl == nil, hasReference(for: documentUrl) {
            Logger.favicons.debug("Keeping existing reference for \(documentUrl.shortDescription); no favicon was found this time")
            return
        }

        guard let host = documentUrl.host else {
            insertToUrlCache(faviconUrls: faviconUrls, documentUrl: documentUrl)
            return
        }

        if let cacheEntry = hostReferences[host] {
            // Host references already cached

            if cacheEntry.smallFaviconUrl == faviconUrls.smallFaviconUrl && cacheEntry.mediumFaviconUrl == faviconUrls.mediumFaviconUrl {
                // Equal

                // There is a possibility of old cache entry in urlReferences
                if urlReferences[documentUrl] != nil {
                    invalidateUrlCache(for: host)
                }
                return
            }

            if cacheEntry.documentUrl == documentUrl {
                // Favicon was updated

                // Exceptions may contain updated favicon if user visited a different documentUrl sooner
                invalidateUrlCache(for: host)
                insertToHostCache(faviconUrls: (faviconUrls.smallFaviconUrl, faviconUrls.mediumFaviconUrl), host: host, documentUrl: documentUrl)
                return
            } else {
                // Exception
                insertToUrlCache(faviconUrls: (faviconUrls.smallFaviconUrl, faviconUrls.mediumFaviconUrl), documentUrl: documentUrl)

                return
            }
        } else {
            // Not cached. Add to cache
            insertToHostCache(faviconUrls: (faviconUrls.smallFaviconUrl, faviconUrls.mediumFaviconUrl), host: host, documentUrl: documentUrl)
            return
        }
    }

    func getFaviconUrl(for documentURL: URL, sizeCategory: Favicon.SizeCategory) -> URL? {
        guard loaded else {
            return nil
        }

        // A URL reference is an exception for one document URL, so it takes precedence, but only
        // if it points to a non-nil favicon URL. Otherwise we fall through to the host reference.
        if let urlCacheEntry = urlReferences[documentURL],
           let faviconUrl = urlCacheEntry.faviconUrl(for: sizeCategory) {
            return faviconUrl
        }

        if let host = documentURL.host, let hostCacheEntry = hostReferences[host] {
            return hostCacheEntry.faviconUrl(for: sizeCategory)
        }

        return nil
    }

    func getFaviconUrl(for host: String, sizeCategory: Favicon.SizeCategory) -> URL? {
        guard loaded else {
            return nil
        }

        return hostReferences[host]?.faviconUrl(for: sizeCategory)
    }

    // MARK: - Clean

    func cleanOld(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager) async {
        let bookmarkedHosts = bookmarkManager.allHosts()
        // Remove host references
        await removeHostReferences(filter: { hostReference in
            let host = hostReference.host
            return hostReference.dateCreated < Date.monthAgo &&
                !fireproofDomains.isFireproof(fireproofDomain: host) &&
                !bookmarkedHosts.contains(host)
        }).value
        // Remove URL references
        await removeUrlReferences(filter: { urlReference in
            guard let host = urlReference.documentUrl.host else {
                return false
            }
            return urlReference.dateCreated < Date.monthAgo &&
                !fireproofDomains.isFireproof(fireproofDomain: host) &&
                !bookmarkedHosts.contains(host)
        }).value
    }

    // MARK: - Burning

    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String>) async {
        let bookmarkedHosts = bookmarkManager.allHosts()
        func isHostApproved(host: String) -> Bool {
            return fireproofDomains.isFireproof(fireproofDomain: host) ||
                bookmarkedHosts.contains(host) ||
                savedLogins.contains(host)
        }

        // Remove host references
        await removeHostReferences(filter: { hostReference in
            let host = hostReference.host
            return !isHostApproved(host: host)
        }).value
        // Remove URL references
        await removeUrlReferences(filter: { urlReference in
            guard let host = urlReference.documentUrl.host else {
                return false
            }
            return !isHostApproved(host: host)
        }).value
    }

    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins logins: Set<String>,
                     exceptHistoryDomains history: Set<String>,
                     tld: TLD) async {
        // Remove host references
        let bookmarkedHosts = bookmarkManager.allHosts()
        await removeHostReferences(filter: { hostReference in
            let host = hostReference.host
            let baseDomain = tld.eTLDplus1(host) ?? ""
            return baseDomains.contains(baseDomain) && !bookmarkedHosts.contains(host) && !logins.contains(host) && !history.contains(host)
        }).value
        // Remove URL references
        await removeUrlReferences(filter: { urlReference in
            guard let host = urlReference.documentUrl.host else {
                return false
            }
            return baseDomains.contains(host) && !bookmarkedHosts.contains(host) && !logins.contains(host) && !history.contains(host)
        }).value
    }

    // MARK: - Debug / admin removal

    @MainActor
    func removeAllReferences() async {
        // Resolve from the store (the source of truth) so a full reset also clears references this
        // in-memory cache may not have loaded yet, rather than only the in-memory ones.
        let (storedHostReferences, storedUrlReferences) = (try? await storing.loadFaviconReferences()) ?? ([], [])
        hostReferences.removeAll()
        urlReferences.removeAll()
        await removeHostReferencesFromStore(storedHostReferences)
        await removeUrlReferencesFromStore(storedUrlReferences)
    }

    // MARK: - Private

    /// Whether a lookup for `documentUrl` already resolves to a favicon URL, at any size category.
    @MainActor
    private func hasReference(for documentUrl: URL) -> Bool {
        if let urlCacheEntry = urlReferences[documentUrl], !urlCacheEntry.isEmpty {
            return true
        }
        if let host = documentUrl.host, let hostCacheEntry = hostReferences[host], !hostCacheEntry.isEmpty {
            return true
        }
        return false
    }

    @MainActor
    private func insertToHostCache(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), host: String, documentUrl: URL) {
        // Remove existing
        if let oldReference = hostReferences[host] {
            Task.detached {
                await self.removeHostReferencesFromStore([oldReference])
            }
        }

        // Create and save new references
        let hostReference = FaviconHostReference(identifier: UUID(),
                                              smallFaviconUrl: faviconUrls.smallFaviconUrl,
                                              mediumFaviconUrl: faviconUrls.mediumFaviconUrl,
                                              host: host,
                                              documentUrl: documentUrl,
                                              dateCreated: Date())
        hostReferences[host] = hostReference

        Task.detached {
            do {
                try await self.storing.save(hostReference: hostReference)
                Logger.favicons.debug("Host reference saved successfully. host: \(hostReference.host)")
            } catch {
                Logger.favicons.error("Saving of host reference failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func insertToUrlCache(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL) {
        // Remove existing
        if let oldReference = urlReferences[documentUrl] {
            Task {
                await self.removeUrlReferencesFromStore([oldReference])
            }
        }

        // Create and save new references
        let urlReference = FaviconUrlReference(identifier: UUID(),
                                             smallFaviconUrl: faviconUrls.smallFaviconUrl,
                                             mediumFaviconUrl: faviconUrls.mediumFaviconUrl,
                                             documentUrl: documentUrl,
                                             dateCreated: Date())

        urlReferences[documentUrl] = urlReference

        Task {
            do {
                try await self.storing.save(urlReference: urlReference)
                Logger.favicons.debug("URL reference saved successfully. document URL: \(urlReference.documentUrl.shortDescription)")
            } catch {
                Logger.favicons.error("Saving of URL reference failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func invalidateUrlCache(for host: String) {
        _ = removeUrlReferences { urlReference in
            urlReference.documentUrl.host == host
        }
    }

    @MainActor
    private func removeHostReferences(filter isRemoved: (FaviconHostReference) -> Bool) -> Task<Void, Never> {
        let hostReferencesToRemove = hostReferences.values.filter(isRemoved)
        hostReferencesToRemove.forEach { hostReferences[$0.host] = nil }

        return Task.detached {
            await self.removeHostReferencesFromStore(hostReferencesToRemove)
        }
    }

    private func removeHostReferencesFromStore(_ hostReferences: [FaviconHostReference]) async {
        guard !hostReferences.isEmpty else { return }

        do {
            try await storing.remove(hostReferences: hostReferences)
            Logger.favicons.debug("Host references removed successfully.")
        } catch {
            Logger.favicons.error("Removing of host references failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func removeUrlReferences(filter isRemoved: (FaviconUrlReference) -> Bool) -> Task<Void, Never> {
        let urlReferencesToRemove = urlReferences.values.filter(isRemoved)
        urlReferencesToRemove.forEach { urlReferences[$0.documentUrl] = nil }

        return Task.detached {
            await self.removeUrlReferencesFromStore(urlReferencesToRemove)
        }
    }

    private func removeUrlReferencesFromStore(_ urlReferences: [FaviconUrlReference]) async {
        guard !urlReferences.isEmpty else { return }

        do {
            try await storing.remove(urlReferences: urlReferences)
            Logger.favicons.debug("URL references removed successfully.")
        } catch {
            Logger.favicons.error("Removing of URL references failed: \(error.localizedDescription)")
        }
    }
}

/// A common protocol for FaviconHostReference and FaviconUrlReference to share favicon URL accessors and
/// resolving a URL for a given size category.
protocol FaviconReferencing {

    var smallFaviconUrl: URL? { get }
    var mediumFaviconUrl: URL? { get }

}

extension FaviconReferencing {

    /// The favicon URL for `sizeCategory`, or `nil` when this reference names none. The small category
    /// accepts the medium favicon as a stand-in, because a medium favicon scales down acceptably.
    func faviconUrl(for sizeCategory: Favicon.SizeCategory) -> URL? {
        switch sizeCategory {
        case .small: return smallFaviconUrl ?? mediumFaviconUrl
        default: return mediumFaviconUrl
        }
    }

    /// Returns `true` when a reference doesn't point to any favicon URL at all.
    var isEmpty: Bool {
        smallFaviconUrl == nil && mediumFaviconUrl == nil
    }

}

extension FaviconHostReference: FaviconReferencing {}
extension FaviconUrlReference: FaviconReferencing {}

extension Array where Element: FaviconReferencing {

    /// Splits the references into the empty ones and the ones that name a favicon URL.
    func extractEmpty() -> (empty: [Element], valid: [Element]) {
        reduce(into: (empty: [Element](), valid: [Element]())) { result, reference in
            if reference.isEmpty {
                result.empty.append(reference)
            } else {
                result.valid.append(reference)
            }
        }
    }

}
