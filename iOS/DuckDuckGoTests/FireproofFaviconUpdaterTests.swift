//
//  FireproofFaviconUpdaterTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import Bookmarks
import Core
import Foundation
import Persistence
import UserScript
import XCTest

@testable import DuckDuckGo

class FireproofFaviconUpdaterTests: XCTestCase, TabNotifying, FaviconProviding {

    var db: CoreDataDatabase!

    var didUpdateFaviconCalled = false
    var replaceFaviconCalled = false

    var loadFaviconDomain: String?
    var loadFaviconURL: URL?
    var loadFaviconCache: FaviconsCacheType?

    var image: UIImage?

    override func setUpWithError() throws {
        try super.setUpWithError()

        let model = CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel")!

        db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        db.loadStore()

        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        BookmarkUtils.prepareFoldersStructure(in: context)
        try context.save()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        try db.tearDown(deleteStores: true)
    }

    @MainActor
    func testWhenBookmarkDoesNotExist_ThenImageNotReplacement() {
        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        let documentUrl = URL(string: "https://example.com")!
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: [], for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconDomain, "example.com")
        XCTAssertEqual(loadFaviconURL, nil)
        XCTAssertEqual(loadFaviconCache, .tabs)

        XCTAssertTrue(didUpdateFaviconCalled)
        XCTAssertFalse(replaceFaviconCalled)
    }

    @MainActor
    func testWhenBookmarkExistsButNoImage_ThenImageNotReplacement() throws {
        try createBookmark()

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        let documentUrl = URL(string: "https://example.com")!
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: [], for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconDomain, "example.com")
        XCTAssertEqual(loadFaviconURL, nil)
        XCTAssertEqual(loadFaviconCache, .tabs)

        XCTAssertTrue(didUpdateFaviconCalled)
        XCTAssertFalse(replaceFaviconCalled)
    }

    @MainActor
    func testWhenBookmarkExistsButAnddImageExists_ThenImageIsReplaced() throws {
        try createBookmark()

        image = UIImage()
        let faviconUrl = URL(string: "https://example.com/favicon.ico")!
        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [FaviconUserScript.FaviconLink(href: faviconUrl, rel: "icon")]

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconDomain, "example.com")
        XCTAssertEqual(loadFaviconURL, faviconUrl)
        XCTAssertEqual(loadFaviconCache, .tabs)

        XCTAssertTrue(didUpdateFaviconCalled)
        XCTAssertTrue(replaceFaviconCalled)
    }

    @MainActor
    func testWhenBookmarkExistsWithWWWPrefixButAnddImageExists_ThenImageIsReplaced() throws {
        try createBookmark()

        image = UIImage()
        let faviconUrl = URL(string: "https://example.com/favicon.ico")!
        let documentUrl = URL(string: "https://www.example.com")!
        let faviconLinks = [FaviconUserScript.FaviconLink(href: faviconUrl, rel: "icon")]

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconDomain, "www.example.com")
        XCTAssertEqual(loadFaviconURL, faviconUrl)
        XCTAssertEqual(loadFaviconCache, .tabs)

        XCTAssertTrue(didUpdateFaviconCalled)
        XCTAssertTrue(replaceFaviconCalled)
    }

    // MARK: - Favicon Selection Tests

    @MainActor
    func testFaviconSelectionPrefersIconOverAppleTouchIcon() throws {
        try createBookmark()
        image = UIImage()

        let iconUrl = URL(string: "https://example.com/favicon.ico")!
        let appleTouchUrl = URL(string: "https://example.com/apple-touch-icon.png")!
        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: appleTouchUrl, rel: "apple-touch-icon"),
            FaviconUserScript.FaviconLink(href: iconUrl, rel: "icon")
        ]

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconURL, iconUrl, "Should prefer 'icon' over 'apple-touch-icon'")
    }

    @MainActor
    func testFaviconSelectionFallsBackToAppleTouchIcon() throws {
        try createBookmark()
        image = UIImage()

        let appleTouchUrl = URL(string: "https://example.com/apple-touch-icon.png")!
        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: appleTouchUrl, rel: "apple-touch-icon")
        ]

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconURL, appleTouchUrl, "Should use apple-touch-icon when no standard icon available")
    }

    @MainActor
    func testFaviconSelectionWithShortcutIcon() throws {
        try createBookmark()
        image = UIImage()

        let shortcutIconUrl = URL(string: "https://example.com/favicon.ico")!
        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: shortcutIconUrl, rel: "shortcut icon")
        ]

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconURL, shortcutIconUrl, "Should handle 'shortcut icon' rel attribute")
    }

    @MainActor
    func testFaviconSelectionPrefersShortcutIconOverAppleTouchIcon() throws {
        try createBookmark()
        image = UIImage()

        let shortcutIconUrl = URL(string: "https://example.com/favicon.ico")!
        let appleTouchUrl = URL(string: "https://example.com/apple-touch-icon.png")!
        let documentUrl = URL(string: "https://example.com")!
        let faviconLinks = [
            FaviconUserScript.FaviconLink(href: appleTouchUrl, rel: "apple-touch-icon"),
            FaviconUserScript.FaviconLink(href: shortcutIconUrl, rel: "shortcut icon")
        ]

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: faviconLinks, for: documentUrl, in: nil)

        XCTAssertEqual(loadFaviconURL, shortcutIconUrl, "Should prefer 'shortcut icon' over 'apple-touch-icon'")
    }

    @MainActor
    func testFaviconSelectionWithEmptyLinks() {
        let documentUrl = URL(string: "https://example.com")!

        let updater = FireproofFaviconUpdater(bookmarksDatabase: db, tab: self, favicons: self)
        updater.faviconUserScript(FaviconUserScript(), didFindFaviconLinks: [], for: documentUrl, in: nil)

        XCTAssertNil(loadFaviconURL, "Should pass nil URL when no favicon links available")
        XCTAssertTrue(didUpdateFaviconCalled, "Should still call didUpdateFavicon even with empty links")
    }

    func didUpdateFavicon() {
        didUpdateFaviconCalled = true
    }

    func loadFavicon(forDomain domain: String, fromURL url: URL?, intoCache cacheType: FaviconsCacheType, completion: ((UIImage?) -> Void)?) {
        loadFaviconDomain = domain
        loadFaviconURL = url
        loadFaviconCache = cacheType
        completion?(image)
    }

    func replaceFireproofFavicon(forDomain domain: String?, withImage: UIImage) {
        replaceFaviconCalled = true
    }

    func createBookmark() throws {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        guard let root = BookmarkUtils.fetchRootFolder(context) else {
            fatalError("failed to fetch root folder")
        }
        _ = BookmarkEntity.makeBookmark(title: "Test", url: "https://www.example.com", parent: root, context: context)
        try context.save()
    }

}

func tempDBDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}
