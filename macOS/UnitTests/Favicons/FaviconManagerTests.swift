//
//  FaviconManagerTests.swift
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

import Combine
import CoreImage
import FeatureFlags_macOS
import PrivacyConfig
import PrivacyConfigTestsUtils
import UserScript
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class FaviconManagerTests: XCTestCase {
    var faviconManager: FaviconManager!
    var imageCache: CapturingFaviconImageCache!
    var referenceCache: CapturingFaviconReferenceCache!
    var featureFlagger: MockFeatureFlagger!

    @MainActor
    override func setUp() async throws {
        imageCache = CapturingFaviconImageCache()
        referenceCache = CapturingFaviconReferenceCache()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.faviconWebKitSVGRendering]
        faviconManager = FaviconManager(
            cacheType: .inMemory,
            bookmarkManager: MockBookmarkManager(),
            fireproofDomains: MockFireproofDomains(domains: []),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger,
            faviconRasterizer: FaviconTestFixtures.makeRasterizer(featureFlagger: featureFlagger),
            imageCache: { _ in self.imageCache },
            referenceCache: { _ in self.referenceCache }
        )
    }

    override func tearDown() {
        faviconManager = nil
        imageCache = nil
        referenceCache = nil
        featureFlagger = nil
    }

    @MainActor
    func testWhenFaviconManagerIsInMemory_ThenItMustInitNullStore() {
        let faviconManager = FaviconManager(
            cacheType: .inMemory,
            bookmarkManager: MockBookmarkManager(),
            fireproofDomains: MockFireproofDomains(domains: []),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            faviconRasterizer: FaviconTestFixtures.makeRasterizer()
        )
        XCTAssertNotNil(faviconManager.store as? FaviconNullStore)
    }

    // MARK: - resolvedCachedFavicon(for host:)

    @MainActor
    func testResolvedCachedFaviconForHostResolvesURLViaHostReferenceAndReturnsDecodedImage() async throws {
        let host = "example.com"
        let faviconURL = try XCTUnwrap("https://example.com/favicon.ico".url)
        let documentURL = try XCTUnwrap("https://example.com".url)
        let image = NSImage(size: NSSize(width: 16, height: 16))

        referenceCache.getFaviconURLForHost = { requestedHost, sizeCategory in
            requestedHost == host && sizeCategory == .small ? faviconURL : nil
        }
        imageCache.getFaviconWithURL = { url in
            url == faviconURL ? Favicon(identifier: UUID(), url: faviconURL, image: image, relation: .favicon, documentUrl: documentURL, dateCreated: Date()) : nil
        }

        let favicon = await faviconManager.resolvedCachedFavicon(for: host, sizeCategory: .small)

        XCTAssertEqual(favicon?.url, faviconURL)
        XCTAssertEqual(favicon?.image, image)
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.map(\.host), [host])
        XCTAssertEqual(imageCache.getFaviconWithURLCalls, [faviconURL])
    }

    @MainActor
    func testResolvedCachedFaviconForHostReturnsNilWhenHostHasNoReference() async {
        referenceCache.getFaviconURLForHost = { _, _ in nil }

        let favicon = await faviconManager.resolvedCachedFavicon(for: "unknown.example", sizeCategory: .small)

        XCTAssertNil(favicon)
        XCTAssertTrue(imageCache.getFaviconWithURLCalls.isEmpty)
    }

    // MARK: - storeFavicon

    /// An SVG on which CoreSVG overflows the stack (root `<svg>` and a child reference the same filter).
    /// It must be rendered by WebKit, which handles it.
    @MainActor
    func testStoreFaviconRasterizesSVGWithWebKit() async throws {
        let documentURL = try XCTUnwrap("https://example.com".url)

        try await faviconManager.storeFavicon(Data(FaviconTestFixtures.recursiveFilterSVG.utf8), with: nil, for: documentURL)

        let stored = try XCTUnwrap(imageCache.insertCalls.first?.first?.image)
        XCTAssertTrue(stored.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertEqual(stored.size, NSSize(width: 64, height: 64))
        XCTAssertTrue(stored.hasVisiblePixels())
    }

    /// With the flag off, the legacy `NSImage(data:)` is kept. A harmless SVG is used: it stays vector-backed.
    @MainActor
    func testStoreFaviconKeepsLegacyDecodingWhenWebKitRenderingIsOff() async throws {
        featureFlagger.enabledFeatureFlags = []
        let documentURL = try XCTUnwrap("https://example.com".url)
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16"/></svg>"##

        try await faviconManager.storeFavicon(Data(svg.utf8), with: nil, for: documentURL)

        let stored = try XCTUnwrap(imageCache.insertCalls.first?.first?.image)
        XCTAssertFalse(stored.representations.contains { $0 is NSBitmapImageRep })
    }

    @MainActor
    func testStoreFaviconIgnoresDataThatIsNotAnImage() async throws {
        let documentURL = try XCTUnwrap("https://example.com".url)

        try await faviconManager.storeFavicon(Data("not an image".utf8), with: nil, for: documentURL)

        XCTAssertTrue(imageCache.insertCalls.isEmpty)
    }

    // MARK: - decodeFavicon (favicons found on a page)

    private func faviconLink(_ path: String = "icon.svg", type: String? = nil) throws -> FaviconUserScript.FaviconLink {
        FaviconUserScript.FaviconLink(href: try XCTUnwrap(URL(string: "https://example.com/\(path)")), rel: "icon", type: type)
    }

    /// An SVG that crashes CoreSVG is rendered by WebKit, and the page favicon is the rendered PNG.
    @MainActor
    func testDecodeFaviconRendersSVGWithWebKit() async throws {
        let svg = Data(FaviconTestFixtures.recursiveFilterSVG.utf8)

        let fetched = try await FaviconManager.decodeFavicon(from: svg, link: faviconLink(), rasterizer: FaviconTestFixtures.makeRasterizer())

        XCTAssertTrue(fetched.isRasterizedVector)
        XCTAssertTrue(fetched.isSVG)
        XCTAssertNotNil(CIImage(data: fetched.data), "The data is the rendered PNG")
        XCTAssertNotEqual(fetched.data, svg)
        XCTAssertTrue(fetched.image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(fetched.image.hasVisiblePixels())
    }

    /// An SVG without a hint in its link (no type, no `.svg` extension) is still recognized as an SVG once rendered.
    @MainActor
    func testDecodeFaviconTreatsARenderedVectorAsSVGWhateverTheLinkSays() async throws {
        let svg = Data(FaviconTestFixtures.svg(width: 16, height: 16).utf8)

        let fetched = try await FaviconManager.decodeFavicon(from: svg, link: faviconLink("icon"), rasterizer: FaviconTestFixtures.makeRasterizer())

        XCTAssertTrue(fetched.isSVG)
    }

    @MainActor
    func testDecodeFaviconKeepsRasterDataAsIs() async throws {
        let rasterizer = FaviconTestFixtures.makeRasterizer()
        let png = try await rasterizer.rasterize(Data(FaviconTestFixtures.svg(width: 16, height: 16).utf8))

        let fetched = try await FaviconManager.decodeFavicon(from: png, link: faviconLink("icon.png"), rasterizer: rasterizer)

        XCTAssertFalse(fetched.isRasterizedVector)
        XCTAssertEqual(fetched.data, png)
    }

    /// An SVG that WebKit renders fully transparent is rejected, so that another favicon is picked.
    @MainActor
    func testDecodeFaviconRejectsAnSVGThatRendersTransparent() async throws {
        let svg = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="none"/></svg>"##.utf8)

        do {
            _ = try await FaviconManager.decodeFavicon(from: svg, link: faviconLink(), rasterizer: FaviconTestFixtures.makeRasterizer())
            XCTFail("Expected the SVG to be rejected")
        } catch {
            XCTAssertEqual(error as? FaviconManager.FaviconDecodingError, .transparentSVG)
        }
    }

    /// With the flag off the legacy decoding is used: the SVG data is kept, not rendered.
    @MainActor
    func testDecodeFaviconWithTheFlagOffKeepsTheSVGData() async throws {
        let svg = Data(FaviconTestFixtures.svg(width: 16, height: 16).utf8)

        let fetched = try await FaviconManager.decodeFavicon(from: svg, link: faviconLink(), rasterizer: FaviconTestFixtures.makeRasterizer(enabled: false))

        XCTAssertFalse(fetched.isRasterizedVector)
        XCTAssertEqual(fetched.data, svg)
    }

    /// A PDF favicon is rendered by WebKit the same way.
    @MainActor
    func testDecodeFaviconRendersAPDFWithWebKit() async throws {
        let pdf = FaviconTestFixtures.pdfData()

        let fetched = try await FaviconManager.decodeFavicon(from: pdf, link: faviconLink("icon.pdf", type: "application/pdf"), rasterizer: FaviconTestFixtures.makeRasterizer())

        XCTAssertTrue(fetched.isRasterizedVector)
        XCTAssertNotEqual(fetched.data, pdf)
        XCTAssertTrue(fetched.image.representations.allSatisfy { $0 is NSBitmapImageRep })
        XCTAssertTrue(fetched.image.hasVisiblePixels())
    }

    /// The flag is read for every favicon, so switching it while the app runs takes effect at once, in both
    /// directions, with the web view of the earlier renders still alive.
    @MainActor
    func testDecodeFaviconFollowsTheFlagWhileTheRasterizerLives() async throws {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.faviconWebKitSVGRendering]
        let rasterizer = FaviconTestFixtures.makeRasterizer(featureFlagger: featureFlagger)
        let svg = Data(FaviconTestFixtures.svg(width: 16, height: 16).utf8)

        let rendered = try await FaviconManager.decodeFavicon(from: svg, link: faviconLink(), rasterizer: rasterizer)
        featureFlagger.enabledFeatureFlags = []
        let legacy = try await FaviconManager.decodeFavicon(from: svg, link: faviconLink(), rasterizer: rasterizer)
        featureFlagger.enabledFeatureFlags = [.faviconWebKitSVGRendering]
        let renderedAgain = try await FaviconManager.decodeFavicon(from: svg, link: faviconLink(), rasterizer: rasterizer)

        XCTAssertTrue(rendered.isRasterizedVector)
        XCTAssertFalse(legacy.isRasterizedVector)
        XCTAssertEqual(legacy.data, svg)
        XCTAssertTrue(renderedAgain.isRasterizedVector)
    }

    /// The same for the favicons stored from bookmarks and sync.
    @MainActor
    func testStoreFaviconFollowsTheFlagWhileTheManagerLives() async throws {
        let documentURL = try XCTUnwrap("https://example.com".url)
        let svg = Data(FaviconTestFixtures.svg(width: 16, height: 16).utf8)

        try await faviconManager.storeFavicon(svg, with: nil, for: documentURL)
        featureFlagger.enabledFeatureFlags = []
        try await faviconManager.storeFavicon(svg, with: nil, for: documentURL)
        featureFlagger.enabledFeatureFlags = [.faviconWebKitSVGRendering]
        try await faviconManager.storeFavicon(svg, with: nil, for: documentURL)

        let isBitmap = try imageCache.insertCalls.map { call in
            try XCTUnwrap(call.first?.image).representations.allSatisfy { $0 is NSBitmapImageRep }
        }
        XCTAssertEqual(isBitmap, [true, false, true])
    }

    @MainActor
    func testDecodeFaviconThrowsForEmptyData() async throws {
        do {
            _ = try await FaviconManager.decodeFavicon(from: Data(), link: faviconLink(), rasterizer: FaviconTestFixtures.makeRasterizer())
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .zeroByteResource)
        }
    }

    @MainActor
    func testDecodeFaviconThrowsForDataThatIsNotAnImage() async throws {
        let notAnImage = Data("not an image".utf8)

        do {
            _ = try await FaviconManager.decodeFavicon(from: notAnImage, link: faviconLink(), rasterizer: FaviconTestFixtures.makeRasterizer())
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? FaviconRasterizer.RasterizationError, .unsupportedData)
        }
        do {
            _ = try await FaviconManager.decodeFavicon(from: notAnImage, link: faviconLink(), rasterizer: FaviconTestFixtures.makeRasterizer(enabled: false))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile)
        }
    }

    // MARK: - fallBackToSmaller

    // MARK: getCachedFaviconURLForDocumentURL

    @MainActor
    func testIfFallBackToSmallerIsFalseThenGetCachedFaviconURLForDocumentURLOnlyChecksProvidedSizeCategory() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForDocumentURL = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        XCTAssertEqual(faviconManager.getCachedFaviconURL(for: url, sizeCategory: .huge, fallBackToSmaller: false), nil)
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.count, 1)
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.first?.sizeCategory, .huge)
    }

    @MainActor
    func testIfFallBackToSmallerIsTrueThenGetCachedFaviconURLForDocumentURLChecksSmallerSizeCategories() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForDocumentURL = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        XCTAssertEqual(faviconManager.getCachedFaviconURL(for: url, sizeCategory: .huge, fallBackToSmaller: true), faviconURL)
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.count, 4)
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.map(\.sizeCategory), [.huge, .large, .medium, .small])
    }

    // MARK: getCachedFaviconForDocumentURL

    @MainActor
    func testIfFallBackToSmallerIsFalseThenGetCachedFaviconForDocumentURLOnlyChecksProvidedSizeCategory() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForDocumentURL = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        imageCache.getFaviconWithURL = { _ in
            Favicon(identifier: UUID(), url: faviconURL, image: nil, relation: .favicon, documentUrl: url, dateCreated: Date())
        }

        XCTAssertNil(faviconManager.getCachedFavicon(for: url, sizeCategory: .huge, fallBackToSmaller: false))
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.count, 1)
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.map(\.sizeCategory), [.huge])
    }

    @MainActor
    func testIfFallBackToSmallerIsTrueThenGetCachedFaviconForDocumentURLOnlyChecksProvidedSizeCategory() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForDocumentURL = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        imageCache.getFaviconWithURL = { _ in
            Favicon(identifier: UUID(), url: faviconURL, image: nil, relation: .favicon, documentUrl: url, dateCreated: Date())
        }

        XCTAssertNotNil(faviconManager.getCachedFavicon(for: url, sizeCategory: .huge, fallBackToSmaller: true))
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.count, 4)
        XCTAssertEqual(referenceCache.getFaviconURLForDocumentURLCalls.map(\.sizeCategory), [.huge, .large, .medium, .small])
    }

    // MARK: getCachedFaviconForHost

    @MainActor
    func testIfFallBackToSmallerIsFalseThenGetCachedFaviconForHostOnlyChecksProvidedSizeCategory() async throws {
        let host = "example.com"
        let url = try XCTUnwrap("https://\(host)".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForHost = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        imageCache.getFaviconWithURL = { _ in
            Favicon(identifier: UUID(), url: faviconURL, image: nil, relation: .favicon, documentUrl: url, dateCreated: Date())
        }

        XCTAssertNil(faviconManager.getCachedFavicon(for: host, sizeCategory: .huge, fallBackToSmaller: false))
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.count, 1)
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.map(\.sizeCategory), [.huge])
    }

    @MainActor
    func testIfFallBackToSmallerIsTrueThenGetCachedFaviconForHostOnlyChecksProvidedSizeCategory() async throws {
        let host = "example.com"
        let url = try XCTUnwrap("https://\(host)".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForHost = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        imageCache.getFaviconWithURL = { _ in
            Favicon(identifier: UUID(), url: faviconURL, image: nil, relation: .favicon, documentUrl: url, dateCreated: Date())
        }

        XCTAssertNotNil(faviconManager.getCachedFavicon(for: host, sizeCategory: .huge, fallBackToSmaller: true))
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.count, 4)
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.map(\.sizeCategory), [.huge, .large, .medium, .small])
    }

    // MARK: getCachedFaviconForDomainOrAnySubdomain

    @MainActor
    func testIfFallBackToSmallerIsFalseThenGetCachedFaviconForDomainOrAnySubdomainOnlyChecksProvidedSizeCategory() async throws {
        let host = "example.com"
        let url = try XCTUnwrap("https://\(host)".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForHost = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        imageCache.getFaviconWithURL = { _ in
            Favicon(identifier: UUID(), url: faviconURL, image: nil, relation: .favicon, documentUrl: url, dateCreated: Date())
        }

        XCTAssertNil(faviconManager.getCachedFavicon(forDomainOrAnySubdomain: host, sizeCategory: .huge, fallBackToSmaller: false))
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.count, 1)
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.map(\.sizeCategory), [.huge])
    }

    @MainActor
    func testIfFallBackToSmallerIsTrueThenGetCachedFaviconForDomainOrAnySubdomainOnlyChecksProvidedSizeCategory() async throws {
        let host = "example.com"
        let url = try XCTUnwrap("https://\(host)".url)
        let faviconURL = try XCTUnwrap("https://favicon.com".url)

        referenceCache.getFaviconURLForHost = { _, sizeCategory in
            sizeCategory == .small ? faviconURL : nil
        }

        imageCache.getFaviconWithURL = { _ in
            Favicon(identifier: UUID(), url: faviconURL, image: nil, relation: .favicon, documentUrl: url, dateCreated: Date())
        }

        XCTAssertNotNil(faviconManager.getCachedFavicon(forDomainOrAnySubdomain: host, sizeCategory: .huge, fallBackToSmaller: true))
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.count, 4)
        XCTAssertEqual(referenceCache.getFaviconURLForHostCalls.map(\.sizeCategory), [.huge, .large, .medium, .small])
    }

    // MARK: - fetchFavicons size selection

    func testFaviconSelectionDropsLargerFaviconsAndSVGsWhenAnExactMaxFaviconExists() {
        let small = FaviconSize(longestSide: 16, isSVG: false)
        let medium = FaviconSize(longestSide: 32, isSVG: false)
        let exactMax = FaviconSize(longestSide: 64, isSVG: false)
        let larger = FaviconSize(longestSide: 256, isSVG: false)
        let svg = FaviconSize(longestSide: 0, isSVG: true)

        // A 64px favicon exists, so the 256px favicon and the SVG are dropped.
        XCTAssertEqual(FaviconManager.faviconsToKeep([small, medium, exactMax, larger, svg], maxStoredSize: 64),
                       [small, medium, exactMax])
    }

    func testFaviconSelectionKeepsSmallestLargerFaviconAndDropsSVGWhenALargerRasterExists() {
        let small = FaviconSize(longestSide: 16, isSVG: false)
        let medium = FaviconSize(longestSide: 32, isSVG: false)
        let smallestLarger = FaviconSize(longestSide: 128, isSVG: false)
        let largest = FaviconSize(longestSide: 256, isSVG: false)
        let svg = FaviconSize(longestSide: 0, isSVG: true)

        // No 64px favicon, but larger rasters exist: keep the smallest larger one (128px), drop 256px, and
        // drop the SVG (a raster already covers the largest displayed size).
        XCTAssertEqual(FaviconManager.faviconsToKeep([small, medium, smallestLarger, largest, svg], maxStoredSize: 64),
                       [small, medium, smallestLarger])
    }

    func testFaviconSelectionKeepsSVGWhenEveryRasterFaviconIsSmallerThanMax() {
        let small = FaviconSize(longestSide: 16, isSVG: false)
        let medium = FaviconSize(longestSide: 32, isSVG: false)
        let svg = FaviconSize(longestSide: 0, isSVG: true)

        // No raster reaches 64px, so the SVG is kept to cover the larger displayed sizes.
        XCTAssertEqual(FaviconManager.faviconsToKeep([small, medium, svg], maxStoredSize: 64),
                       [small, medium, svg])
    }

    func testFaviconSelectionKeepsSVGOnlyWhenThereIsNoRasterFavicon() {
        let svg = FaviconSize(longestSide: 0, isSVG: true)
        XCTAssertEqual(FaviconManager.faviconsToKeep([svg], maxStoredSize: 64), [svg])
    }

    func testFaviconSelectionDropsSVGWhenAnExactMaxFaviconExists() {
        let exactMax = FaviconSize(longestSide: 64, isSVG: false)
        let svg = FaviconSize(longestSide: 0, isSVG: true)
        XCTAssertEqual(FaviconManager.faviconsToKeep([exactMax, svg], maxStoredSize: 64), [exactMax])
    }

    func testFaviconSelectionKeepsEveryFaviconAtOrBelowMax() {
        let favicons = [
            FaviconSize(longestSide: 16, isSVG: false),
            FaviconSize(longestSide: 32, isSVG: false),
            FaviconSize(longestSide: 64, isSVG: false)
        ]
        XCTAssertEqual(FaviconManager.faviconsToKeep(favicons, maxStoredSize: 64), favicons)
    }

    func testFaviconSelectionDeduplicatesSameSize() {
        let favicons = [
            FaviconSize(longestSide: 512, isSVG: true),
            FaviconSize(longestSide: 180, isSVG: false),
            FaviconSize(longestSide: 16, isSVG: false),
            FaviconSize(longestSide: 180, isSVG: false),
            FaviconSize(longestSide: 48, isSVG: false),
            FaviconSize(longestSide: 32, isSVG: false)
        ]
        XCTAssertEqual(
            FaviconManager.faviconsToKeep(favicons, maxStoredSize: 64).sorted(by: { $0.longestSide < $1.longestSide }),
            [
                FaviconSize(longestSide: 16, isSVG: false),
                FaviconSize(longestSide: 32, isSVG: false),
                FaviconSize(longestSide: 48, isSVG: false),
                FaviconSize(longestSide: 180, isSVG: false)
            ]
        )
    }

    func testFaviconSelectionDropsLargestFavicon() {
        let favicons = [
            FaviconSize(longestSide: 48, isSVG: false),
            FaviconSize(longestSide: 114, isSVG: false),
            FaviconSize(longestSide: 144, isSVG: false)
        ]
        XCTAssertEqual(
            FaviconManager.faviconsToKeep(favicons, maxStoredSize: 64).sorted(by: { $0.longestSide < $1.longestSide }),
            [
                FaviconSize(longestSide: 48, isSVG: false),
                FaviconSize(longestSide: 114, isSVG: false)
            ]
        )
    }
}

/// Lightweight `FaviconSizeRepresentable` used to exercise `FaviconManager.faviconsToKeep`.
private struct FaviconSize: FaviconSizeRepresentable, Equatable {
    let longestSide: CGFloat
    let isSVG: Bool
}
