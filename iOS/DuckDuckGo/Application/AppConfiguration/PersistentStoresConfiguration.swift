//
//  PersistentStoresConfiguration.swift
//  DuckDuckGo
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
import Core
import Persistence
import BrowserServicesKit
#if DEBUG
import Bookmarks
import CoreData
import DDGError
#endif
import os.log
import PixelKit

enum DatabaseError {

    case container(Error)
    case other(Error)

}

final class PersistentStoresConfiguration {

    let database = Database.shared
#if DEBUG
    let bookmarksDatabase: CoreDataDatabase
#else
    let bookmarksDatabase = BookmarksDatabase.make()
#endif
    private(set) var sharedSecureVault: (any AutofillSecureVault)?

    private let application: UIApplication
#if DEBUG
    private let usesTemporaryBookmarksStore: Bool
#endif

    init(application: UIApplication = .shared) {
        self.application = application
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let usesTemporaryBookmarksStore = environment["UITEST_MODE"] == "1" && environment["UITEST_TEMPORARY_BOOKMARKS_STORE"] == "1"
        self.usesTemporaryBookmarksStore = usesTemporaryBookmarksStore
        if usesTemporaryBookmarksStore {
            let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            bookmarksDatabase = BookmarksDatabase.make(location: location)
            return
        }
        bookmarksDatabase = BookmarksDatabase.make()
#endif
    }

    func configure(syncKeyValueStore: ThrowingKeyValueStoring,
                   isBookmarksDBFilePresent: Bool?) throws {
        try loadDatabase()
        try loadAndMigrateBookmarksDatabase(syncKeyValueStore: syncKeyValueStore, isBookmarksDBFilePresent: isBookmarksDBFilePresent)
        initializeSharedSecureVault()
    }

    private func loadDatabase() throws {
        var dbError: Error?
        database.loadStore { _, error in
            dbError = error
        }
        if let dbError {
            if let containerError = dbError as? CoreDataDatabase.Error,
               case .containerLocationCouldNotBePrepared(let underlyingError) = containerError {
                throw TerminationError.database(.container(underlyingError))
            } else {
                throw TerminationError.database(.other(dbError))
            }
        }
    }

    private func loadAndMigrateBookmarksDatabase(syncKeyValueStore: ThrowingKeyValueStoring, isBookmarksDBFilePresent: Bool?) throws {
#if DEBUG
        if usesTemporaryBookmarksStore {
            try loadTemporaryBookmarksStore()
            return
        }
#endif
        do {
            // Create a simple counter store with just atomic writes (no encryption for debugging data)
            let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let counterStore = try KeyValueFileStore(location: appSupportDir, name: "BookmarksStructureLostCounter", writeOptions: [.atomic, .noFileProtection])
            let validator = BookmarksDatabaseSetup.makeValidator(counterStore: counterStore, isBookmarksDBFilePresent: isBookmarksDBFilePresent)
            try BookmarksDatabaseSetup().loadStoreAndMigrate(bookmarksDatabase: bookmarksDatabase, validator: validator)
        } catch let error as BookmarksDatabaseError {
            throw TerminationError.bookmarksDatabase(error)
        } catch {
            throw TerminationError.bookmarksDatabase(.other(error))
        }
    }

#if DEBUG
    private enum TemporaryBookmarksStoreError: Int, DDGError {
        case missingRootFolder = 1

        static let errorDomain = "com.duckduckgo.temporaryBookmarksStore"

        var errorCode: Int { rawValue }

        var description: String { "The temporary bookmarks store is missing its root folder." }
    }

    private func loadTemporaryBookmarksStore() throws {
        // Prepare the store before the app creates any bookmark or sync services.
        let folderTitle = ProcessInfo.processInfo.environment["UITEST_BOOKMARKS_FOLDER_WITH_ONE_BOOKMARK"]
        var storeError: Error?
        bookmarksDatabase.loadStore { context, error in
            storeError = error
            if let context {
                BookmarkUtils.prepareFoldersStructure(in: context)
                do {
                    if let folderTitle {
                        guard let root = BookmarkUtils.fetchRootFolder(context) else {
                            throw TemporaryBookmarksStoreError.missingRootFolder
                        }
                        let folder = BookmarkEntity.makeFolder(title: folderTitle, parent: root, context: context)
                        _ = BookmarkEntity.makeBookmark(title: "Example", url: "https://example.com", parent: folder, context: context)
                    }
                    try context.save()
                } catch {
                    storeError = error
                }
            }
        }
        if let storeError {
            throw TerminationError.bookmarksDatabase(.other(storeError))
        }
    }
#endif

    private func initializeSharedSecureVault() {
        guard AutofillSettingStatus.isAutofillEnabledInSettings else {
            return
        }
        do {
            sharedSecureVault = try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
            Logger.general.info("Shared SecureVault initialized at app startup")
        } catch {
            Logger.general.error("Failed to initialize shared SecureVault at startup: \(error.localizedDescription)")
            PixelKit.fire(Pixel.Event.sharedSecureVaultInitFailed.withError(error))
        }
    }

}
