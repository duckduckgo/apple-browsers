//
//  SitePermissionsFaviconStoreTests.swift
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

@_spi(Testing) import Persistence
import Core
import Kingfisher
import SitePermissions
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class SitePermissionsFaviconStoreTests: XCTestCase {

    func testWhenBrowsingCacheHasWWWHostThenRetainsCanonicalImageWithoutFetching() async throws {
        let site = try makeSite("cached.example")
        let store = makeStore(sites: [site])
        let cache = try makeCache()
        let image = makeImage(.red)
        var requestedHosts = [String]()
        let sut = SitePermissionsFaviconStore(store: store, cache: cache, isEnabled: { true }, cachedFavicon: { host in
            requestedHosts.append(host)
            return host == "www.cached.example" ? image : nil
        })

        sut.loadFavicon(for: site)

        XCTAssertEqual(requestedHosts, [site.host, "www." + site.host])
        XCTAssertTrue(sut.viewModel(for: site).image === image)
        let retainedImage = try await diskImage(for: site, in: cache)
        XCTAssertNotNil(retainedImage)
    }

    func testWhenFaviconReachesBrowsingCacheAfterRowIsShownThenLoadUpdatesRowAndRetainsImage() async throws {
        let site = try makeSite("late.example")
        let store = makeStore(sites: [site])
        let cache = try makeCache()
        var browsingImage: UIImage?
        let sut = SitePermissionsFaviconStore(store: store, cache: cache, isEnabled: { true }, cachedFavicon: { _ in browsingImage })
        let row = sut.viewModel(for: site)
        let placeholder = row.image
        sut.loadFavicon(for: site)
        XCTAssertTrue(row.image === placeholder)

        let image = makeImage(.red)
        browsingImage = image
        sut.loadFavicon(for: site)

        XCTAssertTrue(sut.viewModel(for: site) === row)
        XCTAssertTrue(row.image === image)
        let retainedImage = try await diskImage(for: site, in: cache)
        XCTAssertNotNil(retainedImage)
    }

    func testWhenUndoReadsImageBeforeQueuedDeletionThenRestoresDiskCache() async throws {
        let site = try makeSite("queued-undo.example")
        let store = makeStore(sites: [site])
        let cache = try makeCache()
        let imageData = try XCTUnwrap(makeImage(.red).pngData())
        try cache.diskStorage.store(value: imageData, forKey: key(for: site), expiration: .never)
        let sut = SitePermissionsFaviconStore(store: store, cache: cache, isEnabled: { true }, cachedFavicon: { _ in nil })
        let queueBlocked = expectation(description: "Cache IO queue blocked")
        let resumeIO = DispatchSemaphore(value: 0)
        // The untouched callback runs on Kingfisher's serial disk queue.
        cache.retrieveImageInDiskCache(forKey: key(for: site), callbackQueue: .untouch) { _ in
            queueBlocked.fulfill()
            XCTAssertEqual(resumeIO.wait(timeout: .now() + 5), .success)
        }
        await fulfillment(of: [queueBlocked], timeout: 2)

        let snapshot = store.removePermissions(for: site)
        XCTAssertNil(cache.retrieveImageInMemoryCache(forKey: key(for: site)))
        store.restore(snapshot)
        resumeIO.signal()

        let retainedImage = try await diskImage(for: site, in: cache)
        XCTAssertNotNil(retainedImage)
        sut.loadFavicon(for: site)
    }

    func testWhenFeatureIsDisabledThenRetainsNothingButRemovedRecordsStillDeleteTheirImages() async throws {
        let site = try makeSite("disabled.example")
        let removedSite = try makeSite("removed-while-disabled.example")
        let store = makeStore(sites: [site, removedSite])
        let cache = try makeCache()
        let imageData = try XCTUnwrap(makeImage(.blue).pngData())
        try cache.diskStorage.store(value: imageData, forKey: key(for: removedSite), expiration: .never)
        let image = makeImage(.red)
        let sut = SitePermissionsFaviconStore(store: store, cache: cache, isEnabled: { false }, cachedFavicon: { _ in image })

        sut.loadFavicon(for: site)
        store.removePermissions(for: removedSite)

        XCTAssertFalse(sut.viewModel(for: site).image === image)
        XCTAssertNil(cache.retrieveImageInMemoryCache(forKey: key(for: site)))
        let siteImage = try await diskImage(for: site, in: cache)
        let removedImage = try await diskImage(for: removedSite, in: cache)
        XCTAssertNil(siteImage)
        XCTAssertNil(removedImage)
    }

    func testWhenFireClearsPermissionsThenRemovesOnlyUnpreservedFavicons() async throws {
        let removedSite = try makeSite("removed.example")
        let preservedSite = try makeSite("fireproof.example")
        let store = makeStore(sites: [removedSite, preservedSite])
        let cache = try makeCache()
        let image = makeImage(.red)
        let sut = SitePermissionsFaviconStore(store: store, cache: cache, isEnabled: { true }, cachedFavicon: { _ in image })
        let fireproofing = MockFireproofing()
        fireproofing.isAllowedFireproofDomainHandler = { $0 == preservedSite.host }
        let worker = PermissionsFireWorker(store: store, fireproofing: fireproofing, dataClearingWideEventService: nil)

        await worker.burnFireModeData()
        XCTAssertEqual(store.storedSites, [removedSite, preservedSite])
        XCTAssertNotNil(cache.retrieveImageInMemoryCache(forKey: key(for: removedSite)))

        await worker.burnNormalModeData()

        XCTAssertEqual(store.storedSites, [preservedSite])
        XCTAssertNil(cache.retrieveImageInMemoryCache(forKey: key(for: removedSite)))
        let removedImage = try await diskImage(for: removedSite, in: cache)
        let preservedImage = try await diskImage(for: preservedSite, in: cache)
        XCTAssertNil(removedImage)
        XCTAssertNotNil(preservedImage)
        XCTAssertTrue(sut.viewModel(for: preservedSite).image === image)
    }

    func testWhenStartingThenPrunesOrphansAndRetainsOnlyMissingFavicons() async throws {
        let storedSite = try makeSite("stored.example")
        let missingSite = try makeSite("missing.example")
        let orphanedSite = try makeSite("orphaned.example")
        let store = makeStore(sites: [storedSite, missingSite])
        let cache = try makeCache()
        let imageData = try XCTUnwrap(makeImage(.red).pngData())
        for site in [storedSite, orphanedSite] {
            try cache.diskStorage.store(value: imageData, forKey: key(for: site), expiration: .never)
        }
        let browsingImage = makeImage(.blue)
        var requestedHosts = [String]()
        let sut = SitePermissionsFaviconStore(store: store, cache: cache, isEnabled: { true }, cachedFavicon: { host in
            requestedHosts.append(host)
            return host == missingSite.host ? browsingImage : nil
        })

        // Launch looks up only the site that has no image yet.
        XCTAssertEqual(requestedHosts, [missingSite.host])
        sut.loadFavicon(for: storedSite)

        let orphanedImage = try await diskImage(for: orphanedSite, in: cache)
        let storedImage = try await diskImage(for: storedSite, in: cache)
        let missingImage = try await diskImage(for: missingSite, in: cache)
        XCTAssertNil(orphanedImage)
        XCTAssertNotNil(storedImage)
        XCTAssertNotNil(missingImage)
    }

    private func makeStore(sites: Set<SitePermissionKey>) -> SitePermissionsStore {
        let store = SitePermissionsStore(storage: InMemoryKeyValueStore().keyedStoring())
        sites.forEach { store.setPersistentDecision(.allow, for: .camera, at: $0) }
        return store
    }

    private func makeSite(_ host: String) throws -> SitePermissionKey {
        try XCTUnwrap(SitePermissionKey(committedURL: URL(string: "https://" + host)!))
    }

    private func makeCache() throws -> ImageCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try ImageCache(name: "SitePermissionsFaviconStoreTests", cacheDirectoryURL: directory)
        cache.diskStorage.config.usesHashedFileName = false
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return cache
    }

    private func makeImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func key(for site: SitePermissionKey) -> String {
        FaviconHasher.createHash(ofDomain: site.host)
    }

    private func diskImage(for site: SitePermissionKey, in cache: ImageCache) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            cache.retrieveImageInDiskCache(forKey: key(for: site)) { result in
                continuation.resume(with: result)
            }
        }
    }
}
