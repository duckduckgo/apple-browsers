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

import Foundation
import History
@_spi(Testing) import PixelKit
import Testing

@testable import DuckDuckGo_Privacy_Browser
@testable import BrowserServicesKit

class ChromiumDataImporterTests {
    private var createdProfileURLs: [URL] = []

    deinit {
        createdProfileURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check if bookmarks import summary is populated after a successful bookmark import", .timeLimit(.minutes(1)))
    func whenImportingBookmarks_AndBookmarkImportSucceeds_ThenSummaryIsPopulated() async throws {
        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { _, _, _, _ in .init(successful: 1, duplicates: 2, failed: 3) })
        let importer = makeImporter(profileURL: ChromiumBookmarkStore().resourceURL, loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager)

        let result = await importer.importData(types: [.bookmarks])

        #expect(result[.passwords] == nil)
        let bookmarks = try #require(result[.bookmarks]).get()
        #expect(bookmarks.successful == 1)
        #expect(bookmarks.duplicate == 2)
        #expect(bookmarks.failed == 3)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check if bookmarks and custom shortcuts are merged and bookmarks bar is not favorited after importing bookmarks", .timeLimit(.minutes(1)))
    func whenImportingBookmarks_BookmarksAndCustomShortcutsAreMerged_AndBookmarksBarIsNotFavorited() async throws {
        var bookmarksToImport: ImportedBookmarks?
        var bookmarksBarMarkedAsFavorites: Bool?

        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { bookmarks, _, markBookmarksBarAsFavorites, _ in
            bookmarksToImport = bookmarks
            bookmarksBarMarkedAsFavorites = markBookmarksBarAsFavorites
            return .init(successful: 1, duplicates: 2, failed: 3)
        })
        let importer = makeImporter(profileURL: ChromiumBookmarkStore.customShortcuts.resourceURL, loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager)

        _ = await importer.importData(types: [.bookmarks])

        #expect(bookmarksToImport?.numberOfBookmarks == 5)
        #expect(bookmarksBarMarkedAsFavorites == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check if bookmarks and top sites shortcuts are merged and bookmarks bar is not favorited after importing bookmarks", .timeLimit(.minutes(1)))
    func whenImportingBookmarks_BookmarksAndTopSitesShortcutsAreMerged_AndBookmarksBarIsNotFavorited() async throws {
        var bookmarksToImport: ImportedBookmarks?
        var bookmarksBarMarkedAsFavorites: Bool?

        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { bookmarks, _, markBookmarksBarAsFavorites, _ in
            bookmarksToImport = bookmarks
            bookmarksBarMarkedAsFavorites = markBookmarksBarAsFavorites
            return .init(successful: 1, duplicates: 2, failed: 3)
        })
        let importer = makeImporter(profileURL: ChromiumBookmarkStore.topSitesShortcuts.resourceURL, loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager)

        _ = await importer.importData(types: [.bookmarks])

        #expect(bookmarksToImport?.numberOfBookmarks == 6)
        #expect(bookmarksBarMarkedAsFavorites == false)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check if history is imported after the bookmarks import fails", .timeLimit(.minutes(1)))
    func whenImportingBookmarksAndHistory_AndBookmarkImportFails_ThenHistoryIsImported() async throws {
        let parseResult = HistoryImport.ParseResult(visits: [visit(url: "https://duckduckgo.com")], skipped: 1)
        let historyImporter = MockHistoryImporter()
        historyImporter.summary = .init(imported: 2, alreadyInHistory: 1)
        let importer = makeImporter(profileURL: missingProfileURL,
                                    historyReader: MockChromiumHistoryReader(result: .success(parseResult)),
                                    historyImporter: historyImporter)

        let result = await importer.importData(types: [.bookmarks, .history])

        #expect(result[.bookmarks]?.isSuccess == false)
        let history = try #require(result[.history]).get()
        #expect(history.successful == 2)
        #expect(history.duplicate == 1)
        #expect(historyImporter.importedParseResults == [parseResult])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check if a missing History database is reported only when the profile folder has no History file",
          .timeLimit(.minutes(1)),
          arguments: [(profileFiles: ["Bookmarks"], firesPixel: true), (profileFiles: ["Bookmarks", "History"], firesPixel: false)])
    func whenHistoryCantBeRead_ThenSourceFileMissingPixelIsFiredOnlyWithoutHistoryFile(profileFiles: [String], firesPixel: Bool) async throws {
        let pixelKit = PixelKitMock()
        let importer = makeImporter(profileURL: try makeProfile(files: profileFiles),
                                    historyReader: MockChromiumHistoryReader(result: .failure(historyReadError)),
                                    pixelFiring: pixelKit)

        _ = await importer.importData(types: [.history])

        let expectedPixels = firesPixel ? ["dataimport_history_source-file-missing_macos"] : []
        #expect(pixelKit.actualFireCalls.map(\.pixel.name) == expectedPixels)
        #expect(pixelKit.actualFireCalls.allSatisfy { $0.pixel.parameters?["source"] == "chrome" && $0.frequency == .dailyAndCount })
    }

    private var historyReadError: ChromiumHistoryReader.ImportError {
        ChromiumHistoryReader.ImportError(type: .copyTemporaryFile, underlyingError: nil)
    }

    private func makeProfile(files: [String]) throws -> URL {
        let profileURL = missingProfileURL
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        for file in files {
            FileManager.default.createFile(atPath: profileURL.appendingPathComponent(file).path, contents: Data())
        }
        createdProfileURLs.append(profileURL)
        return profileURL
    }

    private var missingProfileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeImporter(
        profileURL: URL,
        loginImporter: LoginImporter? = MockLoginImporter(),
        bookmarkImporter: BookmarkImporter = MockBookmarkImporter(importBookmarks: { _, _, _, _ in .init(successful: 0, duplicates: 0, failed: 0) }),
        faviconManager: FaviconManagement = FaviconManagerMock(),
        historyReader: ChromiumHistoryReaderProtocol = MockChromiumHistoryReader(),
        historyImporter: HistoryImporterProtocol = MockHistoryImporter(),
        pixelFiring: PixelFiring? = nil
    ) -> ChromiumDataImporter {
        ChromiumDataImporter(profile: .init(browser: .chrome, profileURL: profileURL),
                             loginImporter: loginImporter,
                             bookmarkImporter: bookmarkImporter,
                             faviconManager: faviconManager,
                             historyReader: historyReader,
                             historyImporter: historyImporter,
                             pixelFiring: pixelFiring)
    }

    private func visit(url: String) -> HistoryImport.Visit {
        HistoryImport.Visit(url: URL(string: url)!, title: nil, date: Date())
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
