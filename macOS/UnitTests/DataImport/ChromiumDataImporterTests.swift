//
//  ChromiumDataImporterTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Testing
@testable import DuckDuckGo_Privacy_Browser
@testable import BrowserServicesKit

class ChromiumDataImporterTests {

    @Test("Check if bookmarks import summary is populated after a successful bookmark import")
    func whenImportingBookmarks_AndBookmarkImportSucceeds_ThenSummaryIsPopulated() async throws {
        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { _, _, _, _ in .init(successful: 1, duplicates: 2, failed: 3) })
        let featureFlagger = MockFeatureFlagger()
        let importer = ChromiumDataImporter(profile: .init(browser: .chrome, profileURL: ChromiumBookmarkStore().resourceURL), loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager, featureFlagger: featureFlagger)

        let result = await importer.importData(types: [.bookmarks])

        #expect(result[.passwords] == nil)
        let bookmarks = try #require(result[.bookmarks]).get()
        #expect(bookmarks.successful == 1)
        #expect(bookmarks.duplicate == 2)
        #expect(bookmarks.failed == 3)
    }

    @Test("Check if only bookmarks are imported and bookmarks bar is favorited after importing bookmarks with feature flag disabled")
    func whenImportingBookmarks_AndFeatureFlagDisabled_OnlyBookmarksAreMerged_AndBookmarksBarIsFavorited() async throws {
        var bookmarksToImport: ImportedBookmarks?
        var bookmarksBarMarkedAsFavorites: Bool?

        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { bookmarks, _, markBookmarksBarAsFavorites, _ in
            bookmarksToImport = bookmarks
            bookmarksBarMarkedAsFavorites = markBookmarksBarAsFavorites
            return .init(successful: 1, duplicates: 2, failed: 3)
        })
        let featureFlagger = MockFeatureFlagger()
        let importer = ChromiumDataImporter(profile: .init(browser: .chrome, profileURL: ChromiumBookmarkStore.customShortcuts.resourceURL), loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager, featureFlagger: featureFlagger)

        _ = await importer.importData(types: [.bookmarks])

        #expect(bookmarksToImport?.numberOfBookmarks == 4)
        #expect(bookmarksBarMarkedAsFavorites == true)
    }

    @Test("Check if bookmarks and custom shortcuts are merged and bookmarks bar is not favorited after importing bookmarks with feature flag enabled")
    func whenImportingBookmarks_AndFeatureFlagEnabled_BookmarksAndCustomShortcutsAreMerged_AndBookmarksBarIsNotFavorited() async throws {
        var bookmarksToImport: ImportedBookmarks?
        var bookmarksBarMarkedAsFavorites: Bool?

        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { bookmarks, _, markBookmarksBarAsFavorites, _ in
            bookmarksToImport = bookmarks
            bookmarksBarMarkedAsFavorites = markBookmarksBarAsFavorites
            return .init(successful: 1, duplicates: 2, failed: 3)
        })
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags.append(.importChromeShortcuts)
        let importer = ChromiumDataImporter(profile: .init(browser: .chrome, profileURL: ChromiumBookmarkStore.customShortcuts.resourceURL), loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager, featureFlagger: featureFlagger)

        _ = await importer.importData(types: [.bookmarks])

        #expect(bookmarksToImport?.numberOfBookmarks == 5)
        #expect(bookmarksBarMarkedAsFavorites == false)
    }

    @Test("Check if bookmarks and top sites shortcuts are merged and bookmarks bar is not favorited after importing bookmarks with feature flag enabled")
    func whenImportingBookmarks_AndFeatureFlagEnabled_BookmarksAndTopSitesShortcutsAreMerged_AndBookmarksBarIsNotFavorited() async throws {
        var bookmarksToImport: ImportedBookmarks?
        var bookmarksBarMarkedAsFavorites: Bool?

        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { bookmarks, _, markBookmarksBarAsFavorites, _ in
            bookmarksToImport = bookmarks
            bookmarksBarMarkedAsFavorites = markBookmarksBarAsFavorites
            return .init(successful: 1, duplicates: 2, failed: 3)
        })
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags.append(.importChromeShortcuts)
        let importer = ChromiumDataImporter(profile: .init(browser: .chrome, profileURL: ChromiumBookmarkStore.topSitesShortcuts.resourceURL), loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager, featureFlagger: featureFlagger)

        _ = await importer.importData(types: [.bookmarks])

        #expect(bookmarksToImport?.numberOfBookmarks == 6)
        #expect(bookmarksBarMarkedAsFavorites == false)
    }

}

extension ChromiumDataImporter {
    func importData(types: Set<DataImport.DataType>) async -> DataImportSummary {
        return await importData(types: types).task.value
    }
}

private struct ChromiumBookmarkStore {
    static let topSitesShortcuts: Self = .init(directory: "ShortcutsTopSites")
    static let customShortcuts: Self = .init(directory: "ShortcutsCustom")

    var directory: String = ""

    var resourceURL: URL {
        let bundle = Bundle(for: ChromiumDataImporterTests.self)
        return bundle.resourceURL!
            .appendingPathComponent("DataImportResources/TestChromeData")
            .appendingPathComponent(directory)
    }
}
