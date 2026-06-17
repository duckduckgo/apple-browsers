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
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class FaviconManagerTests: XCTestCase {
    var faviconManager: FaviconManager!
    var imageCache: CapturingFaviconImageCache!
    var referenceCache: CapturingFaviconReferenceCache!

    @MainActor
    override func setUp() async throws {
        imageCache = CapturingFaviconImageCache()
        referenceCache = CapturingFaviconReferenceCache()
        faviconManager = FaviconManager(
            cacheType: .inMemory,
            bookmarkManager: MockBookmarkManager(),
            fireproofDomains: MockFireproofDomains(domains: []),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            imageCache: { _ in self.imageCache },
            referenceCache: { _ in self.referenceCache }
        )
    }

    override func tearDown() {
        faviconManager = nil
        imageCache = nil
        referenceCache = nil
    }

    @MainActor
    func testWhenFaviconManagerIsInMemory_ThenItMustInitNullStore() {
        let faviconManager = FaviconManager(
            cacheType: .inMemory,
            bookmarkManager: MockBookmarkManager(),
            fireproofDomains: MockFireproofDomains(domains: []),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
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

    // MARK: getCachedFavicon(forUrlOrAnySubdomain:)

    @MainActor
    func testFaviconForURLOrAnySubdomainReturnsCachedFaviconForSameHostmaneWithDivergentSubdomain() async throws {
        let host = "example.com"
        let domainURL = try XCTUnwrap("https://\(host)".url)
        let faviconURL = try XCTUnwrap("https://www.\(host)/path/favicon.ico".url)

        let cacheMap: [URL: Favicon] = [
            faviconURL: Favicon(identifier: UUID(), url: faviconURL, image: nil, relation: .favicon, documentUrl: domainURL, dateCreated: Date())
        ]

        referenceCache.getFaviconURLForHost = { _, _ in
            faviconURL
        }

        imageCache.getFaviconWithURL = { url in
            cacheMap[url]
        }

        XCTAssertNil(faviconManager.getCachedFavicon(for: domainURL, sizeCategory: .small))
        XCTAssertNotNil(faviconManager.getCachedFavicon(forUrlOrAnySubdomain: domainURL, sizeCategory: .small, fallBackToSmaller: false))
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
