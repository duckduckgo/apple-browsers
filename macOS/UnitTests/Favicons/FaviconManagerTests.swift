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

import XCTest
import Combine
@testable import DuckDuckGo_Privacy_Browser

class FaviconManagerTests: XCTestCase {
    var faviconManager: FaviconManager!
    var imageCache: CapturingFaviconImageCache!
    var referenceCache: CapturingFaviconReferenceCache!

    @MainActor
    override func setUp() async throws {
        imageCache = CapturingFaviconImageCache()
        referenceCache = CapturingFaviconReferenceCache()
        faviconManager = FaviconManager(cacheType: .inMemory, bookmarkManager: MockBookmarkManager(), imageCache: { _ in self.imageCache }, referenceCache: { _ in self.referenceCache })
    }

    @MainActor
    func testWhenFaviconManagerIsInMemory_ThenItMustInitNullStore() {
        let faviconManager = FaviconManager(cacheType: .inMemory, bookmarkManager: MockBookmarkManager())
        XCTAssertNotNil(faviconManager.store as? FaviconNullStore)
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
}
