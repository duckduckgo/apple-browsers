//
//  ChromiumDataImporter.swift
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

import AppKit
import BrowserServicesKit
import Foundation
import History
import PixelKit

internal class ChromiumDataImporter: DataImporter {

    private let bookmarkImporter: BookmarkImporter
    private let loginImporter: LoginImporter?
    private let faviconManager: FaviconManagement
    private let historyReader: ChromiumHistoryReaderProtocol
    private let historyImporter: HistoryImporterProtocol
    private let pixelFiring: PixelFiring?
    private let profile: DataImport.BrowserProfile
    private var source: DataImport.Source {
        profile.browser.importSource
    }

    init(
        profile: DataImport.BrowserProfile,
        loginImporter: LoginImporter?,
        bookmarkImporter: BookmarkImporter,
        faviconManager: FaviconManagement,
        historyReader: ChromiumHistoryReaderProtocol,
        historyImporter: HistoryImporterProtocol,
        pixelFiring: PixelFiring? = PixelKit.shared
    ) {
        self.profile = profile
        self.loginImporter = loginImporter
        self.bookmarkImporter = bookmarkImporter
        self.faviconManager = faviconManager
        self.historyReader = historyReader
        self.historyImporter = historyImporter
        self.pixelFiring = pixelFiring
    }

    convenience init(profile: DataImport.BrowserProfile, loginImporter: LoginImporter?, bookmarkImporter: BookmarkImporter) {
        self.init(profile: profile,
                  loginImporter: loginImporter,
                  bookmarkImporter: bookmarkImporter,
                  faviconManager: NSApp.delegateTyped.faviconManager,
                  historyReader: ChromiumHistoryReader(chromiumDataDirectoryURL: profile.profileURL),
                  historyImporter: HistoryImporter(historyCoordinator: NSApp.delegateTyped.historyCoordinator))
    }

    var importableTypes: [DataImport.DataType] {
        return [.passwords, .bookmarks, .history]
    }

    func importData(types: Set<DataImport.DataType>) -> DataImportTask {
        .detachedWithProgress { updateProgress in
            do {
                let result = try await self.importDataSync(types: types, updateProgress: updateProgress)
                return result
            } catch is CancellationError {
            } catch {
                assertionFailure("Only CancellationError should be thrown here")
            }
            return [:]
        }
    }

    private func importDataSync(types: Set<DataImport.DataType>, updateProgress: @escaping DataImportProgressCallback) async throws -> DataImportSummary {
        var summary = DataImportSummary()

        let dataTypeFraction = 1.0 / Double(types.count)

        if types.contains(.passwords), let loginImporter {
            try updateProgress(.importingPasswords(numberOfPasswords: nil, fraction: 0.0))

            let loginReader = ChromiumLoginReader(chromiumDataDirectoryURL: profile.profileURL, source: source)
            let loginResult = loginReader.readLogins(modalWindow: nil)

            let loginsSummary = try loginResult.flatMap { logins in
                do {
                    return try .success(loginImporter.importLogins(logins, reporter: SecureVaultReporter.shared) { count in
                        try updateProgress(.importingPasswords(numberOfPasswords: count,
                                                               fraction: dataTypeFraction * (0.5 + Double(count) / Double(logins.count))))
                    })
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return .failure(LoginImporterError(error: error))
                }
            }

            summary[.passwords] = loginsSummary

            try updateProgress(.importingPasswords(numberOfPasswords: try? loginResult.get().count, fraction: dataTypeFraction * 1.0))
        }

        // don‘t proceed with bookmarks and history import on Keychain prompt denial
        let isKeychainPromptDenied = (summary[.passwords]?.error as? ChromiumLoginReader.ImportError)?.type == .userDeniedKeychainPrompt

        let passwordsFraction: Double = types.contains(.passwords) ? dataTypeFraction : 0.0
        bookmarksImport: if types.contains(.bookmarks), !isKeychainPromptDenied {

            try updateProgress(.importingBookmarks(numberOfBookmarks: nil, fraction: passwordsFraction + 0.0))

            let bookmarkReader = ChromiumBookmarksReader(chromiumDataDirectoryURL: profile.profileURL)
            let bookmarkResult = bookmarkReader.readBookmarks()

            guard case .success(var importedBookmarks) = bookmarkResult else {
                summary[.bookmarks] = .failure(bookmarkResult.error!)
                break bookmarksImport
            }

            let newTabShortcuts = fetchShortcutsAsFavorites()
            FavoritesImportProcessor.mergeBookmarksAndFavorites(bookmarks: &importedBookmarks, favorites: newTabShortcuts)

            try updateProgress(.importingBookmarks(numberOfBookmarks: importedBookmarks.numberOfBookmarks,
                                                   fraction: passwordsFraction + dataTypeFraction * 0.5))

            let bookmarksSummary = bookmarkImporter.importBookmarks(importedBookmarks, source: .thirdPartyBrowser(source), markRootBookmarksAsFavoritesByDefault: false, maxFavoritesCount: nil)

            await importFavicons()

            summary[.bookmarks] = .success(.init(bookmarksSummary))

            try updateProgress(.importingBookmarks(numberOfBookmarks: importedBookmarks.numberOfBookmarks,
                                                   fraction: passwordsFraction + dataTypeFraction * 1.0))
        }

        if types.contains(.history), !isKeychainPromptDenied {
            let historyFraction = dataTypeFraction * Double(types.intersection([.passwords, .bookmarks]).count)
            try updateProgress(.importingHistory(numberOfVisits: nil, fraction: historyFraction))

            let historySummary = try await importHistory()
            summary[.history] = historySummary

            try updateProgress(.importingHistory(numberOfVisits: try? historySummary.get().successful,
                                                 fraction: historyFraction + dataTypeFraction))
        }

        return summary
    }

    private func importHistory() async throws -> DataImportResult<DataImport.DataTypeSummary> {
        let parseResult: HistoryImport.ParseResult
        switch historyReader.readVisits(since: .monthAgo) {
        case .success(let result):
            parseResult = result
        case .failure(let error):
            fireHistorySourceFileMissingPixelIfNeeded()
            return .failure(error)
        }
        // reading a large database can take a while: don't add visits to history after the import was cancelled
        try Task.checkCancellation()

        do {
            let importSummary = try await historyImporter.importVisits(parseResult)
            return .success(.init(successful: importSummary.imported, duplicate: importSummary.alreadyInHistory, failed: 0))
        } catch {
            return .failure(ChromiumHistoryReader.ImportError(type: .importVisits, underlyingError: error))
        }
    }

    /// The profile folder could be read, but it has no history database where the importer looks for it.
    private func fireHistorySourceFileMissingPixelIfNeeded() {
        guard profile.validateProfileData() != nil, !profile.hasValidProfileData(for: .history) else { return }

        let pixel = DataImportHistoryPixel.sourceFileMissing(
            source: source.pixelSourceParameterName,
            sourceVersion: profile.installedAppsMajorVersionDescription()
        )
        pixelFiring?.fire(pixel, frequency: .dailyAndCount)
    }

    private func importFavicons() async {
        let faviconsReader = ChromiumFaviconsReader(chromiumDataDirectoryURL: profile.profileURL)
        let faviconsResult = faviconsReader.readFavicons()
        let sourceVersion = profile.installedAppsMajorVersionDescription()

        switch faviconsResult {
        case .success(let faviconsByURL):
            let faviconsByDocument = faviconsByURL.reduce(into: [URL: [Favicon]]()) { result, pair in
                guard let pageURL = URL(string: pair.key) else { return }
                let favicons = pair.value.map {
                    Favicon(identifier: UUID(),
                            url: pageURL,
                            image: $0.image,
                            relation: .icon,
                            documentUrl: pageURL,
                            dateCreated: Date())
                }
                result[pageURL] = favicons
            }
            await faviconManager.handleFaviconsByDocumentUrl(faviconsByDocument)
            PixelKit.fire(GeneralPixel.dataImportSucceeded(action: .favicons, source: source.pixelSourceParameterName, sourceVersion: sourceVersion), frequency: .dailyAndStandard)
        case .failure(let error):
            PixelKit.fire(GeneralPixel.dataImportFailed(source: source.pixelSourceParameterName, sourceVersion: sourceVersion, error: error), frequency: .dailyAndStandard)
        }
    }

    private func fetchShortcutsAsFavorites() -> [ImportedBookmarks.BookmarkOrFolder] {
        let sourceVersion = profile.installedAppsMajorVersionDescription()

        do {
            let preferences = try ChromiumPreferences(profileURL: profile.profileURL)
            var favorites: [ImportedBookmarks.BookmarkOrFolder] = []
            guard preferences.isNewTabShortcutsEnabled else {
                PixelKit.fire(GeneralPixel.favoritesImportSucceeded(source: source.pixelSourceParameterName, sourceVersion: sourceVersion, favoritesBucket: .none), frequency: .dailyAndStandard)
                return favorites
            }

            switch preferences.newTabPageShortcutStyle {
            case .autoGenerated:
                let topSitesReader = ChromiumTopSitesReader(chromiumDataDirectoryURL: profile.profileURL)
                let autoGeneratedShortcuts = try topSitesReader.readTopSites().get()
                favorites = autoGeneratedShortcuts.prefix(8).map { shortcut in
                    ImportedBookmarks.BookmarkOrFolder.bookmark(name: shortcut.title,
                                                                urlString: shortcut.url,
                                                                isDDGFavorite: true,
                                                                favoritesIndex: shortcut.urlRank)
                }
            case .custom:
                let customShortcuts = preferences.customShortcuts
                favorites = customShortcuts.enumerated().map { (index, shortcut) in
                    ImportedBookmarks.BookmarkOrFolder.bookmark(name: shortcut.title,
                                                                urlString: shortcut.url,
                                                                isDDGFavorite: true,
                                                                favoritesIndex: index)
                }
            }

            PixelKit.fire(GeneralPixel.favoritesImportSucceeded(source: source.pixelSourceParameterName, sourceVersion: sourceVersion, favoritesBucket: .init(count: favorites.count)), frequency: .dailyAndStandard)

            return favorites
        } catch {
            PixelKit.fire(GeneralPixel.favoritesImportFailed(source: source.pixelSourceParameterName, sourceVersion: sourceVersion, error: error), frequency: .dailyAndStandard)
            return []
        }
    }

    func requiresKeychainPassword(for selectedDataTypes: Set<DataImport.DataType>) -> Bool {
        return selectedDataTypes.contains(.passwords)
    }

}
