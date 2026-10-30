//
//  FirefoxDataImporterTests.swift
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

import Foundation
import History
@_spi(Testing) import PixelKit
import SharedTestUtilities
import XCTest

@testable import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

class FirefoxDataImporterTests: XCTestCase {

    @MainActor
    func testWhenImportingBookmarks_AndBookmarkImportSucceeds_ThenSummaryIsPopulated() async {
        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { _, _, _, _ in .init(successful: 1, duplicates: 2, failed: 3) })
        let importer = makeImporter(profileURL: resourceURL(), loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager)

        let result = await importer.importData(types: [.bookmarks])

        XCTAssertNil(result[.passwords])
        if case let .success(bookmarks) = result[.bookmarks] {
            XCTAssertEqual(bookmarks.successful, 1)
            XCTAssertEqual(bookmarks.duplicate, 2)
            XCTAssertEqual(bookmarks.failed, 3)
        } else {
            XCTFail("Received populated summary unexpectedly")
        }
    }

    @MainActor
    func testWhenImportingBookmarks_BookmarksAndFavoritesAreMerged_AndBookmarksBarIsNotFavorited() async {
        var bookmarksToImport: ImportedBookmarks?
        var bookmarksBarMarkedAsFavorites: Bool?

        let loginImporter = MockLoginImporter()
        let faviconManager = FaviconManagerMock()
        let bookmarkImporter = MockBookmarkImporter(importBookmarks: { bookmarks, _, markBookmarksBarAsFavorites, _ in
            bookmarksToImport = bookmarks
            bookmarksBarMarkedAsFavorites = markBookmarksBarAsFavorites
            return .init(successful: 1, duplicates: 2, failed: 3)
        })
        let importer = makeImporter(profileURL: resourceURL(), loginImporter: loginImporter, bookmarkImporter: bookmarkImporter, faviconManager: faviconManager)

        _ = await importer.importData(types: [.bookmarks])

        XCTAssertEqual(bookmarksToImport?.numberOfBookmarks, 14)
        XCTAssertEqual(bookmarksBarMarkedAsFavorites, false)
    }

    @MainActor
    func testWhenImportingBookmarksAndHistory_AndBookmarkImportFails_ThenHistoryIsImported() async throws {
        let parseResult = HistoryImport.ParseResult(visits: [visit(url: "https://duckduckgo.com")], skipped: 1)
        let historyImporter = MockHistoryImporter()
        historyImporter.summary = .init(imported: 2, alreadyInHistory: 1)
        let importer = makeImporter(profileURL: missingProfileURL,
                                    historyReader: MockFirefoxHistoryVisitsReader(result: .success(parseResult)),
                                    historyImporter: historyImporter)

        let result = await importer.importData(types: [.bookmarks, .history])

        XCTAssertEqual(result[.bookmarks]?.isSuccess, false)
        let history = try XCTUnwrap(result[.history]).get()
        XCTAssertEqual(history.successful, 2)
        XCTAssertEqual(history.duplicate, 1)
        XCTAssertEqual(historyImporter.importedParseResults, [parseResult])
    }

    @MainActor
    func testWhenHistoryCantBeRead_AndProfileHasNoPlacesDatabase_ThenSourceFileMissingPixelIsFired() async throws {
        let pixelKit = PixelKitMock()
        let importer = makeImporter(profileURL: try makeProfile(files: ["logins.json"]),
                                    historyReader: MockFirefoxHistoryVisitsReader(result: .failure(historyReadError)),
                                    pixelFiring: pixelKit)

        _ = await importer.importData(types: [.history])

        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.name), ["dataimport_history_source-file-missing_macos"])
        XCTAssertEqual(pixelKit.actualFireCalls.first?.pixel.parameters?["source"], "firefox")
        XCTAssertEqual(pixelKit.actualFireCalls.first?.frequency, .dailyAndCount)
    }

    @MainActor
    func testWhenHistoryCantBeRead_AndProfileHasPlacesDatabase_ThenSourceFileMissingPixelIsNotFired() async throws {
        let pixelKit = PixelKitMock()
        let importer = makeImporter(profileURL: try makeProfile(files: ["logins.json", "places.sqlite"]),
                                    historyReader: MockFirefoxHistoryVisitsReader(result: .failure(historyReadError)),
                                    pixelFiring: pixelKit)

        _ = await importer.importData(types: [.history])

        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
    }

    private var historyReadError: FirefoxHistoryVisitsReader.ImportError {
        FirefoxHistoryVisitsReader.ImportError(type: .copyTemporaryFile, underlyingError: nil)
    }

    private func makeProfile(files: [String]) throws -> URL {
        let profileURL = missingProfileURL
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        for file in files {
            FileManager.default.createFile(atPath: profileURL.appendingPathComponent(file).path, contents: Data())
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: profileURL) }
        return profileURL
    }

    private var missingProfileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeImporter(
        profileURL: URL,
        loginImporter: LoginImporter = MockLoginImporter(),
        bookmarkImporter: BookmarkImporter = MockBookmarkImporter(importBookmarks: { _, _, _, _ in .init(successful: 0, duplicates: 0, failed: 0) }),
        faviconManager: FaviconManagement = FaviconManagerMock(),
        historyReader: FirefoxHistoryVisitsReaderProtocol = MockFirefoxHistoryVisitsReader(),
        historyImporter: HistoryImporterProtocol = MockHistoryImporter(),
        pixelFiring: PixelFiring? = nil
    ) -> FirefoxDataImporter {
        FirefoxDataImporter(profile: .init(browser: .firefox, profileURL: profileURL),
                            primaryPassword: nil,
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

    private func resourceURL() -> URL {
        let bundle = Bundle(for: FirefoxBookmarksReaderTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData")
    }
}

extension FirefoxDataImporter {
    func importData(types: Set<DataImport.DataType>) async -> DataImportSummary {
        return await importData(types: types).task.value
    }
}
