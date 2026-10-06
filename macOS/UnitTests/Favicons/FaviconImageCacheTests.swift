//
//  FaviconImageCacheTests.swift
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

import AppKit
import Foundation
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class FaviconImageCacheTests: XCTestCase {

    private func makeBitmapImage(pixelsWide: Int, pixelsHigh: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
        image.addRepresentation(rep)
        return image
    }

    // MARK: pixelCost (F5)

    func testPixelCostReflectsRealPixelBytes() {
        let image = makeBitmapImage(pixelsWide: 100, pixelsHigh: 50)
        let cost = FaviconImageCache.pixelCost(of: image)
        // At least width × height × 4 (RGBA); allow modest row padding but not a wildly larger value.
        XCTAssertGreaterThanOrEqual(cost, 100 * 50 * 4)
        XCTAssertLessThan(cost, 100 * 50 * 4 * 4)
    }

    func testPixelCostIsNeverZeroForNonEmptyImage() {
        let image = makeBitmapImage(pixelsWide: 1, pixelsHigh: 1)
        XCTAssertGreaterThan(FaviconImageCache.pixelCost(of: image), 0)
    }

    // MARK: lazy FaviconImageCache (F1 / F2)

    @MainActor
    func testLazyCacheColdPathReturnsMetadataOnlyThenLoadsImageAsync() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]
        store.imagesByIdentifier = [identifier: makeBitmapImage(pixelsWide: 32, pixelsHigh: 32)]

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        let cacheUpdated = expectation(forNotification: .faviconCacheUpdated, object: nil)

        // Cold path: metadata is present but the image hasn't been decoded yet.
        let cold = cache.get(faviconUrl: faviconURL)
        XCTAssertEqual(cold?.url, faviconURL)
        XCTAssertNil(cold?.image)

        await fulfillment(of: [cacheUpdated], timeout: 5)

        // Hot path: the image was loaded off-main, cached, and is now returned synchronously.
        let hot = cache.get(faviconUrl: faviconURL)
        XCTAssertNotNil(hot?.image)
        XCTAssertEqual(store.loadImageCallCount, 1)
        XCTAssertEqual(store.loadImageIdentifiers, [identifier])
    }

    @MainActor
    func testLazyCacheReturnsNilForUnknownURL() async throws {
        let store = FaviconStoringMock()
        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        let unknown = try XCTUnwrap("https://unknown.example/favicon.ico".url)
        XCTAssertNil(cache.get(faviconUrl: unknown))
        XCTAssertEqual(store.loadImageCallCount, 0)
    }

    @MainActor
    func testLazyCacheCoalescesConcurrentColdLoadsForSameURL() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]
        store.imagesByIdentifier = [identifier: makeBitmapImage(pixelsWide: 32, pixelsHigh: 32)]

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        let cacheUpdated = expectation(forNotification: .faviconCacheUpdated, object: nil)

        // Two cold misses for the same URL before the async decode completes must
        // coalesce into a single store.loadImage call.
        _ = cache.get(faviconUrl: faviconURL)
        _ = cache.get(faviconUrl: faviconURL)

        await fulfillment(of: [cacheUpdated], timeout: 5)
        XCTAssertEqual(store.loadImageCallCount, 1)
    }

    // MARK: insert store-write serialization (race)

    @MainActor
    func testConcurrentInsertsForSameURLLeaveExactlyOneStoredRow() async throws {
        let store = RecordingFaviconStore()
        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)

        // Each insert persists a freshly-identified row that is meant to supersede the previous row for
        // the same favicon URL (remove the old row, save the new one). Fire many back-to-back: without
        // serialized store writes, a later insert's removal can run before an earlier insert's save lands,
        // so the superseded row is never deleted and survives as a duplicate.
        let insertCount = 25
        let cacheUpdated = expectation(forNotification: .faviconCacheUpdated, object: nil)
        cacheUpdated.expectedFulfillmentCount = insertCount

        for _ in 0..<insertCount {
            cache.insert([
                Favicon(identifier: UUID(),
                        url: faviconURL,
                        image: makeBitmapImage(pixelsWide: 16, pixelsHigh: 16),
                        relation: .favicon,
                        documentUrl: documentURL,
                        dateCreated: Date())
            ])
        }

        await fulfillment(of: [cacheUpdated], timeout: 10)

        XCTAssertEqual(store.savedCount(forURL: faviconURL), 1,
                       "Exactly one row should remain for a single favicon URL after concurrent inserts")
    }

    // MARK: eager fallback cache (faviconLazyImageLoading kill switch OFF)

    @MainActor
    func testEagerCacheLoadsImagesEagerlyAndReturnsThemSynchronously() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        store.faviconsToLoad = [
            Favicon(identifier: UUID(),
                    url: faviconURL,
                    image: makeBitmapImage(pixelsWide: 32, pixelsHigh: 32),
                    relation: .favicon,
                    documentUrl: documentURL,
                    dateCreated: Date())
        ]

        let cache = EagerFaviconImageCache(faviconStoring: store)
        try await cache.load()

        let result = cache.get(faviconUrl: faviconURL)
        XCTAssertNotNil(result?.image)
        // The eager cache loads everything up front via loadFavicons and never uses
        // the on-demand loadImage path.
        XCTAssertEqual(store.loadFaviconsCallCount, 1)
        XCTAssertEqual(store.loadImageCallCount, 0)
    }

    @MainActor
    func testEagerCacheConcurrentInsertsForSameURLLeaveExactlyOneStoredRow() async throws {
        let store = RecordingFaviconStore()
        let cache = EagerFaviconImageCache(faviconStoring: store)
        try await cache.load()

        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)

        // Same serialization invariant as the lazy cache: superseding inserts must not leave duplicates.
        let insertCount = 25
        let cacheUpdated = expectation(forNotification: .faviconCacheUpdated, object: nil)
        cacheUpdated.expectedFulfillmentCount = insertCount

        for _ in 0..<insertCount {
            cache.insert([
                Favicon(identifier: UUID(),
                        url: faviconURL,
                        image: makeBitmapImage(pixelsWide: 16, pixelsHigh: 16),
                        relation: .favicon,
                        documentUrl: documentURL,
                        dateCreated: Date())
            ])
        }

        await fulfillment(of: [cacheUpdated], timeout: 10)

        XCTAssertEqual(store.savedCount(forURL: faviconURL), 1,
                       "Exactly one row should remain for a single favicon URL after concurrent inserts")
    }

    // MARK: async get

    @MainActor
    func testAsyncGetAwaitsImageDecodeThenServesFromCache() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]
        store.imagesByIdentifier = [identifier: makeBitmapImage(pixelsWide: 32, pixelsHigh: 32)]

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        // Cache miss: the async get awaits the off-main decode and returns the favicon WITH its image.
        let favicon = await cache.resolvedFavicon(faviconUrl: faviconURL)
        XCTAssertNotNil(favicon?.image)
        XCTAssertEqual(store.loadImageCallCount, 1)

        // Second async get is a cache hit — no further decode.
        let cached = await cache.resolvedFavicon(faviconUrl: faviconURL)
        XCTAssertNotNil(cached?.image)
        XCTAssertEqual(store.loadImageCallCount, 1)
    }

    // MARK: debug / admin removal (Favicon Browser)

    @MainActor
    func testRemoveFaviconsWithIdentifiersDeletesFromCacheAndStoreAndNotifies() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        let cacheUpdated = expectation(forNotification: .faviconCacheUpdated, object: nil)
        await cache.removeFavicons(withIdentifiers: [identifier])
        await fulfillment(of: [cacheUpdated], timeout: 5)

        // Removed from the in-memory metadata map and from the store.
        XCTAssertNil(cache.get(faviconUrl: faviconURL))
        XCTAssertEqual(store.removedFaviconIdentifiers, [identifier])
    }

    @MainActor
    func testRemoveFaviconsWithUnknownIdentifierDoesNothing() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        store.metadataToLoad = [
            FaviconMetadata(identifier: UUID(), url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        await cache.removeFavicons(withIdentifiers: [UUID()])

        XCTAssertNotNil(cache.get(faviconUrl: faviconURL))
        XCTAssertTrue(store.removedFaviconIdentifiers.isEmpty)
    }

    @MainActor
    func testRemoveAllFaviconsDeletesEveryRecord() async throws {
        let store = FaviconStoringMock()
        let url1 = try XCTUnwrap("https://a.example/favicon.ico".url)
        let url2 = try XCTUnwrap("https://b.example/favicon.ico".url)
        let id1 = UUID()
        let id2 = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: id1, url: url1, documentUrl: try XCTUnwrap("https://a.example".url), dateCreated: Date(), relation: .favicon),
            FaviconMetadata(identifier: id2, url: url2, documentUrl: try XCTUnwrap("https://b.example".url), dateCreated: Date(), relation: .icon)
        ]

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        await cache.removeAllFavicons()

        XCTAssertNil(cache.get(faviconUrl: url1))
        XCTAssertNil(cache.get(faviconUrl: url2))
        XCTAssertEqual(Set(store.removedFaviconIdentifiers), [id1, id2])
    }

    @MainActor
    func testRemoveFaviconsWithIdentifiersDeletesFromStoreEvenBeforeCacheLoaded() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]

        let cache = FaviconImageCache(faviconStoring: store)
        // Intentionally not loaded: the in-memory metadata map is empty, but the store has the row.
        await cache.removeFavicons(withIdentifiers: [identifier])

        XCTAssertEqual(store.removedFaviconIdentifiers, [identifier])
    }

    @MainActor
    func testRemoveAllFaviconsDeletesFromStoreEvenBeforeCacheLoaded() async throws {
        let store = FaviconStoringMock()
        let id1 = UUID()
        let id2 = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: id1, url: try XCTUnwrap("https://a.example/favicon.ico".url), documentUrl: try XCTUnwrap("https://a.example".url), dateCreated: Date(), relation: .favicon),
            FaviconMetadata(identifier: id2, url: try XCTUnwrap("https://b.example/favicon.ico".url), documentUrl: try XCTUnwrap("https://b.example".url), dateCreated: Date(), relation: .icon)
        ]

        let cache = FaviconImageCache(faviconStoring: store)
        // Intentionally not loaded.
        await cache.removeAllFavicons()

        XCTAssertEqual(Set(store.removedFaviconIdentifiers), [id1, id2])
    }

    // MARK: undecodable image cleanup

    @MainActor
    func testAsyncGetDeletesFaviconWhenImageIsUndecodable() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]
        // The stored bitmap can't be decoded: loadImage reports a decoding failure.
        store.loadImageError = FaviconStore.FaviconStoreError.imageDecodingFailed

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        let favicon = await cache.resolvedFavicon(faviconUrl: faviconURL)
        XCTAssertNil(favicon?.image)

        // The corrupt favicon is deleted from the store...
        XCTAssertEqual(store.removeFaviconsCallCount, 1)
        XCTAssertEqual(store.removedFaviconIdentifiers, [identifier])
        // ...and dropped from the in-memory caches so it's no longer served.
        XCTAssertNil(cache.get(faviconUrl: faviconURL))
    }

    @MainActor
    func testLazyCacheColdPathDeletesFaviconWhenImageIsUndecodable() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]
        // The stored bitmap can't be decoded: loadImage reports a decoding failure.
        store.loadImageError = FaviconStore.FaviconStoreError.imageDecodingFailed

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        // The off-main removal is asynchronous; wait until the store delete is invoked.
        let removed = expectation(description: "corrupt favicon removed from store")
        store.removeFaviconsExpectation = removed

        // Cold path kicks off the off-main decode, which fails.
        let cold = cache.get(faviconUrl: faviconURL)
        XCTAssertNil(cold?.image)

        await fulfillment(of: [removed], timeout: 5)

        // The corrupt favicon is deleted from the store...
        XCTAssertEqual(store.removeFaviconsCallCount, 1)
        XCTAssertEqual(store.removedFaviconIdentifiers, [identifier])
        // ...and dropped from the in-memory caches so it's no longer served.
        XCTAssertNil(cache.get(faviconUrl: faviconURL))
    }

    @MainActor
    func testAsyncGetKeepsFaviconWhenImageLoadFailsWithTransientError() async throws {
        let store = FaviconStoringMock()
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let identifier = UUID()
        store.metadataToLoad = [
            FaviconMetadata(identifier: identifier, url: faviconURL, documentUrl: documentURL, dateCreated: Date(), relation: .favicon)
        ]
        // A transient failure (e.g. a Core Data fetch error), NOT an undecodable image.
        store.loadImageError = TestError.transientFailure

        let cache = FaviconImageCache(faviconStoring: store)
        try await cache.load()

        let favicon = await cache.resolvedFavicon(faviconUrl: faviconURL)
        XCTAssertNil(favicon?.image)

        // A transient failure must NOT delete the favicon...
        XCTAssertEqual(store.removeFaviconsCallCount, 0)
        XCTAssertTrue(store.removedFaviconIdentifiers.isEmpty)
        // ...and the favicon must still be served from the cache.
        XCTAssertNotNil(cache.get(faviconUrl: faviconURL))
    }
}

private enum TestError: Error {
    case transientFailure
}

/// A favicon store that records persisted favicons (honoring removals) so tests can assert how many rows
/// survive for a given favicon URL. `save` yields a few times before recording to widen the window in
/// which a concurrent insert's removal can race ahead of this save — surfacing duplicate rows when
/// inserts aren't serialized.
private final class RecordingFaviconStore: FaviconStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var savedFavicons: [Favicon] = []

    func savedCount(forURL url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return savedFavicons.filter { $0.url == url }.count
    }

    func loadFavicons() async throws -> [Favicon] { [] }
    func loadFaviconMetadata() async throws -> [FaviconMetadata] { [] }
    func loadImage(for identifier: UUID) async throws -> NSImage? { nil }

    func save(_ favicons: [Favicon]) async throws {
        // Suspend a few times so a concurrent insert's removal can interleave before this save records —
        // exactly the window that produces duplicate rows when store writes aren't serialized.
        for _ in 0..<4 { await Task.yield() }
        lock.lock()
        savedFavicons.append(contentsOf: favicons)
        lock.unlock()
    }

    func removeFavicons(_ favicons: [Favicon]) async throws {
        let identifiers = Set(favicons.map(\.identifier))
        lock.lock()
        savedFavicons.removeAll { identifiers.contains($0.identifier) }
        lock.unlock()
    }

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) { ([], []) }
    func save(hostReference: FaviconHostReference) async throws {}
    func save(urlReference: FaviconUrlReference) async throws {}
    func remove(hostReferences: [FaviconHostReference]) async throws {}
    func remove(urlReferences: [FaviconUrlReference]) async throws {}
}
