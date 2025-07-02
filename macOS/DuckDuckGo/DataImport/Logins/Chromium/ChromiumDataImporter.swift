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
import PixelKit
import CryptoKit

internal class ChromiumDataImporter: DataImporter {

    private let bookmarkImporter: BookmarkImporter
    private let loginImporter: LoginImporter?
    private let faviconManager: FaviconManagement
    private let profile: DataImport.BrowserProfile
    private var source: DataImport.Source {
        profile.browser.importSource
    }
    private let featureFlagger: FeatureFlagger

    init(profile: DataImport.BrowserProfile, loginImporter: LoginImporter?, bookmarkImporter: BookmarkImporter, faviconManager: FaviconManagement, featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger) {
        self.profile = profile
        self.loginImporter = loginImporter
        self.bookmarkImporter = bookmarkImporter
        self.faviconManager = faviconManager
        self.featureFlagger = featureFlagger
    }

    convenience init(profile: DataImport.BrowserProfile, loginImporter: LoginImporter?, bookmarkImporter: BookmarkImporter) {
        self.init(profile: profile,
                  loginImporter: loginImporter,
                  bookmarkImporter: bookmarkImporter,
                  faviconManager: NSApp.delegateTyped.faviconManager)
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

        let passwordsFraction: Double = types.contains(.passwords) ? 0.5 : 0.0
        if types.contains(.bookmarks)
            // don‘t proceed with bookmarks import on Keychain prompt denial
            && (summary[.passwords]?.error as? ChromiumLoginReader.ImportError)?.type != .userDeniedKeychainPrompt {

            try updateProgress(.importingBookmarks(numberOfBookmarks: nil, fraction: passwordsFraction + 0.0))

            let bookmarkReader = ChromiumBookmarksReader(chromiumDataDirectoryURL: profile.profileURL)
            let bookmarkResult = bookmarkReader.readBookmarks()

            try updateProgress(.importingBookmarks(numberOfBookmarks: try? bookmarkResult.get().numberOfBookmarks,
                                                   fraction: passwordsFraction + dataTypeFraction * 0.5))

            let bookmarksSummary = bookmarkResult.map { bookmarks in
                let mergedBookmarks = mergeShortcutsWithBookmarks(bookmarks)
                return bookmarkImporter.importBookmarks(mergedBookmarks, source: .thirdPartyBrowser(source))
            }

            if case .success = bookmarksSummary {
                await importFavicons()
            }

            summary[.bookmarks] = bookmarksSummary.map { .init($0) }

            try updateProgress(.importingBookmarks(numberOfBookmarks: try? bookmarkResult.get().numberOfBookmarks,
                                                   fraction: passwordsFraction + dataTypeFraction * 1.0))
        }

        return summary
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
            PixelKit.fire(GeneralPixel.dataImportSucceeded(action: .favicons, source: source, sourceVersion: sourceVersion))
        case .failure(let error):
            PixelKit.fire(GeneralPixel.dataImportFailed(source: source, sourceVersion: sourceVersion, error: error))
        }
    }

    private func fetchShortcutsAsFavorites() -> [ImportedBookmarks.BookmarkOrFolder] {
        do {
            let preferences = try ChromiumPreferences(profileURL: profile.profileURL)
            guard preferences.isNewTabShortcutsEnabled else {
                return []
            }

            if preferences.isUsingAutoGeneratedShortcuts {
                let topSitesReader = ChromiumTopSitesReader(chromiumDataDirectoryURL: profile.profileURL)
                let autoGeneratedShortcuts = try topSitesReader.readTopSites().get()
                return autoGeneratedShortcuts.prefix(8).map { shortcut in
                    ImportedBookmarks.BookmarkOrFolder(name: shortcut.title,
                                                       type: .bookmark,
                                                       urlString: shortcut.url,
                                                       children: nil,
                                                       isDDGFavorite: true)
                }
            } else {
                let customShortcuts = preferences.customShortcuts
                return customShortcuts.map { shortcut in
                    ImportedBookmarks.BookmarkOrFolder(name: shortcut.title,
                                                       type: .bookmark,
                                                       urlString: shortcut.url,
                                                       children: nil,
                                                       isDDGFavorite: true)
                }
            }
        } catch {
            return []
        }
    }

    private func mergeShortcutsWithBookmarks(_ bookmarks: ImportedBookmarks) -> ImportedBookmarks {
        guard featureFlagger.isFeatureOn(.updatedBookmarksFavoritesImport) else {
            return bookmarks
        }

        let shortcuts = fetchShortcutsAsFavorites()
        guard !shortcuts.isEmpty else {
            return bookmarks
        }

        // Create sets of shortcut URLs for efficient lookup
        let shortcutURLs = Set(shortcuts.compactMap { $0.urlString })

        // Recursively process bookmarks to mark matching URLs as favorites
        func processBookmarkOrFolder(_ item: ImportedBookmarks.BookmarkOrFolder) -> ImportedBookmarks.BookmarkOrFolder {
            var updatedItem = item

            // If this is a bookmark and its URL matches a shortcut, mark as favorite
            if !item.isFolder, let urlString = item.urlString, shortcutURLs.contains(urlString) {
                updatedItem.isDDGFavorite = true
            }

            // Recursively process children if this is a folder
            if item.isFolder, let children = item.children {
                let updatedChildren = children.map(processBookmarkOrFolder)
                updatedItem = ImportedBookmarks.BookmarkOrFolder.folder(
                    name: item.name,
                    children: updatedChildren
                )
            }

            return updatedItem
        }

        // Process all top-level folders
        let updatedBookmarkBar = bookmarks.topLevelFolders.bookmarkBar.map(processBookmarkOrFolder)
        let updatedOtherBookmarks = bookmarks.topLevelFolders.otherBookmarks.map(processBookmarkOrFolder)
        let updatedSyncedBookmarks = bookmarks.topLevelFolders.syncedBookmarks.map(processBookmarkOrFolder)

        // Find shortcuts that don't have matching bookmarks and add them to bookmark bar
        let existingBookmarkURLs = collectAllBookmarkURLs(from: bookmarks)
        let uniqueShortcuts = shortcuts.filter { shortcut in
            guard let urlString = shortcut.urlString else {
                return false
            }
            return !existingBookmarkURLs.contains(urlString)
        }
        let mergedBookmarkBar: ImportedBookmarks.BookmarkOrFolder? = {
            guard !uniqueShortcuts.isEmpty else {
                return updatedBookmarkBar
            }
            let existingChildren = updatedBookmarkBar?.children ?? []
            let newChildren = existingChildren + uniqueShortcuts
            return ImportedBookmarks.BookmarkOrFolder.folder(name: updatedBookmarkBar?.name ?? "",
                                                             children: newChildren)
        }()

        let updatedTopLevelFolders = ImportedBookmarks.TopLevelFolders(
            bookmarkBar: mergedBookmarkBar,
            otherBookmarks: updatedOtherBookmarks,
            syncedBookmarks: updatedSyncedBookmarks
        )

        return ImportedBookmarks(topLevelFolders: updatedTopLevelFolders)
    }

    private func collectAllBookmarkURLs(from bookmarks: ImportedBookmarks) -> Set<String> {
        var urls = Set<String>()

        func collectFromFolder(_ folder: ImportedBookmarks.BookmarkOrFolder?) {
            guard let folder = folder else { return }

            if let urlString = folder.urlString {
                urls.insert(urlString)
            }

            folder.children?.forEach(collectFromFolder)
        }

        collectFromFolder(bookmarks.topLevelFolders.bookmarkBar)
        collectFromFolder(bookmarks.topLevelFolders.otherBookmarks)
        collectFromFolder(bookmarks.topLevelFolders.syncedBookmarks)

        return urls
    }

    func requiresKeychainPassword(for selectedDataTypes: Set<DataImport.DataType>) -> Bool {
        return selectedDataTypes.contains(.passwords)
    }

}
