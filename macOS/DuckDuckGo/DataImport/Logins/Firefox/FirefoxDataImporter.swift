//
//  FirefoxDataImporter.swift
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

import Foundation
import SecureStorage
import PixelKit
import BrowserServicesKit

internal class FirefoxDataImporter: DataImporter {

    private let loginImporter: LoginImporter
    private let bookmarkImporter: BookmarkImporter
    private let faviconManager: FaviconManagement
    private let profile: DataImport.BrowserProfile
    private let featureFlagger: FeatureFlagger
    private var source: DataImport.Source {
        profile.browser.importSource
    }

    private let primaryPassword: String?

    init(profile: DataImport.BrowserProfile, primaryPassword: String?, loginImporter: LoginImporter, bookmarkImporter: BookmarkImporter, faviconManager: FaviconManagement, featureFlagger: FeatureFlagger) {
        self.profile = profile
        self.primaryPassword = primaryPassword
        self.loginImporter = loginImporter
        self.bookmarkImporter = bookmarkImporter
        self.faviconManager = faviconManager
        self.featureFlagger = featureFlagger
    }

    var importableTypes: [DataImport.DataType] {
        return [.passwords, .bookmarks]
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

        if types.contains(.passwords) {
            try updateProgress(.importingPasswords(numberOfPasswords: nil, fraction: 0.0))

            let loginReader = FirefoxLoginReader(firefoxProfileURL: profile.profileURL, primaryPassword: self.primaryPassword)
            let loginResult = loginReader.readLogins(dataFormat: nil)

            try updateProgress(.importingPasswords(numberOfPasswords: try? loginResult.get().count, fraction: dataTypeFraction * 0.5))

            let loginsSummary = try loginResult.flatMap { logins in
                do {
                    return try .success(loginImporter.importLogins(logins, reporter: SecureVaultReporter.shared) { count in
                        try updateProgress(.importingPasswords(numberOfPasswords: count,
                                                               fraction: dataTypeFraction * (0.5 + 0.5 * Double(count) / Double(logins.count))))
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

        let passwordsFraction: Double = types.contains(.passwords) ? 0.5 : 0.0
        if types.contains(.bookmarks)
            // don‘t proceed with bookmarks import on invalid Primary Password
            && (summary[.passwords]?.error as? FirefoxLoginReader.ImportError)?.type != .requiresPrimaryPassword {

            try updateProgress(.importingBookmarks(numberOfBookmarks: nil, fraction: passwordsFraction + 0.0))

            let bookmarkReader = FirefoxBookmarksReader(firefoxDataDirectoryURL: profile.profileURL, featureFlagger: featureFlagger)
            let bookmarkResult = bookmarkReader.readBookmarks()

            guard case .success(var importedBookmarks) = bookmarkResult else {
                summary[.bookmarks] = .failure(bookmarkResult.error!)
                return summary
            }

            var markRootBookmarksAsFavoritesByDefault = true
            if featureFlagger.isFeatureOn(.updateFirefoxBookmarksImport) {
                markRootBookmarksAsFavoritesByDefault = false
                let newTabFavorites = fetchNewTabFavorites()
                FavoritesImportProcessor.mergeBookmarksAndFavorites(bookmarks: &importedBookmarks, favorites: newTabFavorites)
            }

            try updateProgress(.importingBookmarks(numberOfBookmarks: importedBookmarks.numberOfBookmarks,
                                                   fraction: passwordsFraction + dataTypeFraction * 0.5))

            let bookmarksSummary = bookmarkImporter.importBookmarks(importedBookmarks, source: .thirdPartyBrowser(source), markRootBookmarksAsFavoritesByDefault: markRootBookmarksAsFavoritesByDefault, maxFavoritesCount: nil)

            await importFavicons()

            summary[.bookmarks] = .success(.init(bookmarksSummary))

            try updateProgress(.importingBookmarks(numberOfBookmarks: importedBookmarks.numberOfBookmarks,
                                                   fraction: passwordsFraction + dataTypeFraction * 1.0))
        }
        try updateProgress(.done)

        return summary
    }

    private func importFavicons() async {
        let faviconsReader = FirefoxFaviconsReader(firefoxDataDirectoryURL: profile.profileURL)
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

    /// requires primary password?
    func validateAccess(for selectedDataTypes: Set<DataImport.DataType>) -> [DataImport.DataType: any DataImportError]? {
        guard selectedDataTypes.contains(.passwords) else { return nil }

        let loginReader = FirefoxLoginReader(firefoxProfileURL: profile.profileURL, primaryPassword: primaryPassword)
        do {
            _=try loginReader.getEncryptionKey()
            return nil

        } catch let error as FirefoxLoginReader.ImportError where error.type == .requiresPrimaryPassword {
            return [.passwords: error]
        } catch {
            return nil
        }
    }

    private func fetchNewTabFavorites() -> [ImportedBookmarks.BookmarkOrFolder] {
        do {
            let preferences = try FirefoxPreferences(profileURL: profile.profileURL)
            guard preferences.newTabFavoritesEnabled else {
                return []
            }

            let favoritesCount = preferences.newTabFavoritesCount
            let pinnedSites = preferences.newTabPinnedSites
                .prefix(favoritesCount)
                .map { site -> ImportedBookmarks.BookmarkOrFolder? in
                    guard let site else { return nil }
                    return ImportedBookmarks.BookmarkOrFolder(name: site.label ?? site.url, type: .bookmark, urlString: site.url, children: nil, isDDGFavorite: true)
                }
            let historyReader = FirefoxHistoryReader(firefoxDataDirectoryURL: profile.profileURL)
            let frecentSites = try historyReader.readFrecentSites().get()
                .reduce(into: (seen: Set<URL>(), result: [ImportedBookmarks.BookmarkOrFolder]())) { partialResult, site in
                    // Filter out URLs that are blocked, the root domain is pinned, or not HTTP/HTTPS.
                    // Then, de-duplicate remaining frecent sites by their root domain.
                    guard let url = URL(string: site.url),
                            !preferences.isURLBlockedOnNewTab(site.url),
                            !pinnedSites.contains(where: { $0?.url?.root == url.root }) else { return }
                    let rootDomain = url.root ?? url
                    if !partialResult.seen.contains(rootDomain) {
                        partialResult.seen.insert(rootDomain)
                        let favorite = ImportedBookmarks.BookmarkOrFolder(name: site.title ?? site.url, type: .bookmark, urlString: site.url, children: nil, isDDGFavorite: true, favoritesIndex: partialResult.result.count)
                        partialResult.result.append(favorite)
                    }
                }
                .result.prefix(favoritesCount).map { $0 }

            guard !pinnedSites.isEmpty else {
                return frecentSites
            }

            // Combine pinned sites and frecent sites to create favorites.
            // The pinned sites array contains nil values as placeholders for frecent sites that are not pinned.
            var favorites: [ImportedBookmarks.BookmarkOrFolder] = []
            var frecentIterator = frecentSites.makeIterator()

            for idx in 0..<favoritesCount {
                if idx < pinnedSites.count, var pinnedSite = pinnedSites[idx] {
                    pinnedSite.favoritesIndex = idx
                    favorites.append(pinnedSite)
                } else if let frecentSite = frecentIterator.next() {
                    var updatedFrecentSite = frecentSite
                    updatedFrecentSite.favoritesIndex = idx
                    favorites.append(updatedFrecentSite)
                }
            }

            return favorites
        } catch {
            // Send pixel for error: https://app.asana.com/1/137249556945/task/1210674932129670
            return []
        }
    }

}
