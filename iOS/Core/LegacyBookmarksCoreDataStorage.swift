//
//  LegacyBookmarksCoreDataStorage.swift
//  DuckDuckGo
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
import CoreData
import Bookmarks

public enum BookmarksDatabaseError: Error {
    // Legacy storage errors
    case noDBSchemeFound
    case unableToLoadPersistentStores(Error)
    case errorCreatingTopLevelBookmarksFolder
    case errorCreatingTopLevelFavoritesFolder
    case couldNotFixBookmarkFolder
    case couldNotFixFavoriteFolder
    
    // Migration errors
    case couldNotPrepareBookmarksDBStructure(Error)
    case couldNotWriteToBookmarksDB(Error)
    
    // Database setup errors
    case couldNotGetFavoritesOrder(Error)
    case couldNotPrepareDatabase(Error)
    
    // Generic
    case other(Error)

    public var name: String {
        switch self {
        case .noDBSchemeFound:
            return "noDBSchemeFound"
        case .unableToLoadPersistentStores:
            return "unableToLoadPersistentStores"
        case .errorCreatingTopLevelBookmarksFolder:
            return "errorCreatingTopLevelBookmarksFolder"
        case .errorCreatingTopLevelFavoritesFolder:
            return "errorCreatingTopLevelFavoritesFolder"
        case .couldNotFixBookmarkFolder:
            return "couldNotFixBookmarkFolder"
        case .couldNotFixFavoriteFolder:
            return "couldNotFixFavoriteFolder"
        case .couldNotPrepareBookmarksDBStructure:
            return "couldNotPrepareBookmarksDBStructure"
        case .couldNotWriteToBookmarksDB:
            return "couldNotWriteToBookmarksDB"
        case .couldNotGetFavoritesOrder:
            return "couldNotGetFavoritesOrder"
        case .couldNotPrepareDatabase:
            return "couldNotPrepareDatabase"
        case .other:
            return "other"
        }
    }
}

public class LegacyBookmarksCoreDataStorage {

    private let storeLoadedCondition = RunLoop.ResumeCondition()
    internal var persistentContainer: NSPersistentContainer

    public lazy var viewContext: NSManagedObjectContext = {
        RunLoop.current.run(until: storeLoadedCondition)
        let context = persistentContainer.viewContext
        context.mergePolicy = NSMergePolicy(merge: .rollbackMergePolicyType)
        context.name = Constants.viewContextName
        return context
    }()

    public func getTemporaryPrivateContext() -> NSManagedObjectContext {
        RunLoop.current.run(until: storeLoadedCondition)
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        context.name = Constants.privateContextName
        return context
    }

    private var cachedReadOnlyTopLevelBookmarksFolder: BookmarkFolderManagedObject?
    private var cachedReadOnlyTopLevelFavoritesFolder: BookmarkFolderManagedObject?

    internal static func getManagedObjectModel() throws -> NSManagedObjectModel {
        let coreBundle = Bundle(identifier: "com.duckduckgo.mobile.ios.Core")!
        guard let managedObjectModel = NSManagedObjectModel.mergedModel(from: [coreBundle]) else {
            throw BookmarksDatabaseError.noDBSchemeFound
        }
        return managedObjectModel
    }

    private var storeDescription: NSPersistentStoreDescription {
        return NSPersistentStoreDescription(url: storeURL)
    }

    public static var defaultStoreURL: URL {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BookmarksDatabase.Constants.bookmarksGroupID)!
        return containerURL.appendingPathComponent("\(Constants.databaseName).sqlite")
    }

    private let storeURL: URL

    public init?(storeURL: URL = defaultStoreURL, createIfNeeded: Bool = false) throws {
        if !FileManager.default.fileExists(atPath: storeURL.path),
           createIfNeeded == false {
            return nil
        }

        self.storeURL = storeURL

        let managedObjectModel = try Self.getManagedObjectModel()
        persistentContainer = NSPersistentContainer(name: Constants.databaseName, managedObjectModel: managedObjectModel)
        persistentContainer.persistentStoreDescriptions = [storeDescription]
    }

    public func removeStore() {

        typealias StoreInfo = (url: URL?, type: String)

        do {
            var storesToDelete = [StoreInfo]()
            for store in persistentContainer.persistentStoreCoordinator.persistentStores {
                storesToDelete.append((url: store.url, type: store.type))
                try persistentContainer.persistentStoreCoordinator.remove(store)
            }

            for (url, type) in storesToDelete {
                if let url = url {
                    try persistentContainer.persistentStoreCoordinator.destroyPersistentStore(at: url,
                                                                                              ofType: type)
                }
            }
        } catch {
            Pixel.fire(pixel: .bookmarksMigrationCouldNotRemoveOldStore,
                       error: error)
        }

        try? FileManager.default.removeItem(atPath: storeURL.path)
        try? FileManager.default.removeItem(atPath: storeURL.path.appending("-wal"))
        try? FileManager.default.removeItem(atPath: storeURL.path.appending("-shm"))
    }

    public func loadStoreAndCaches(andMigrate handler: @escaping (NSManagedObjectContext) -> Void = { _ in }) throws {

        try loadStore(andMigrate: handler)

        RunLoop.current.run(until: storeLoadedCondition)
        try cacheReadOnlyTopLevelBookmarksFolder()
        try cacheReadOnlyTopLevelFavoritesFolder()
    }

    internal func loadStore(andMigrate handler: @escaping (NSManagedObjectContext) -> Void = { _ in }) throws {

        let managedObjectModel = try Self.getManagedObjectModel()
        persistentContainer = NSPersistentContainer(name: Constants.databaseName, managedObjectModel: managedObjectModel)
        persistentContainer.persistentStoreDescriptions = [storeDescription]
        
        var loadError: Error?
        persistentContainer.loadPersistentStores { _, error in
            if let error = error {
                loadError = error
            } else {
                let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                context.persistentStoreCoordinator = self.persistentContainer.persistentStoreCoordinator
                context.name = "Migration"
                context.performAndWait {
                    handler(context)
                    self.storeLoadedCondition.resolve()
                }
            }
        }
        
        if let loadError = loadError {
            throw BookmarksDatabaseError.unableToLoadPersistentStores(loadError)
        }
    }

    static internal func rootFolderManagedObject(_ context: NSManagedObjectContext) throws -> BookmarkFolderManagedObject {
        guard let bookmarksFolder = NSEntityDescription.insertNewObject(forEntityName: "BookmarkFolderManagedObject", into: context)
                as? BookmarkFolderManagedObject else {
            throw BookmarksDatabaseError.errorCreatingTopLevelBookmarksFolder
        }

        bookmarksFolder.isFavorite = false
        return bookmarksFolder
    }

    static internal func rootFavoritesFolderManagedObject(_ context: NSManagedObjectContext) throws -> BookmarkFolderManagedObject {
        guard let bookmarksFolder = NSEntityDescription.insertNewObject(forEntityName: "BookmarkFolderManagedObject", into: context)
                as? BookmarkFolderManagedObject else {
            throw BookmarksDatabaseError.errorCreatingTopLevelFavoritesFolder
        }

        bookmarksFolder.isFavorite = true
        return bookmarksFolder
    }
}

// MARK: public interface
extension LegacyBookmarksCoreDataStorage {

    public var topLevelBookmarksFolder: BookmarkFolderManagedObject? {
        guard let folder = cachedReadOnlyTopLevelBookmarksFolder else {
            return nil
        }
        return folder
    }

    public var topLevelFavoritesFolder: BookmarkFolderManagedObject? {
        guard let folder = cachedReadOnlyTopLevelFavoritesFolder else {
            return nil
        }
        return folder
    }

    public var topLevelBookmarksItems: [BookmarkItemManagedObject] {
        guard let folder = cachedReadOnlyTopLevelBookmarksFolder else {
            return []
        }
        return folder.children?.array as? [BookmarkItemManagedObject] ?? []
    }

}

// MARK: private
extension LegacyBookmarksCoreDataStorage {

    internal enum TopLevelFolderType {
        case favorite
        case bookmark
    }

    /*
     This function will return nil if the database desired structure is not met
     i.e: If there are more than one root level folder OR
     if there is less than one root level folder
     */
    internal func fetchReadOnlyTopLevelFolder(withFolderType
                                             folderType: TopLevelFolderType) -> BookmarkFolderManagedObject? {

        var folder: BookmarkFolderManagedObject?

        viewContext.performAndWait {
            let fetchRequest = NSFetchRequest<BookmarkFolderManagedObject>(entityName: Constants.folderClassName)
            fetchRequest.predicate = NSPredicate(format: "%K == nil AND %K == %@",
                                                 #keyPath(BookmarkManagedObject.parent),
                                                 #keyPath(BookmarkManagedObject.isFavorite),
                                                 NSNumber(value: folderType == .favorite))

            let results = try? viewContext.fetch(fetchRequest)
            guard (results?.count ?? 0) == 1,
                  let fetchedFolder = results?.first else {
                return
            }

            folder = fetchedFolder
        }
        return folder
    }

    internal func cacheReadOnlyTopLevelBookmarksFolder() throws {
        guard let folder = fetchReadOnlyTopLevelFolder(withFolderType: .bookmark) else {
            try fixFolderDataStructure(withFolderType: .bookmark)

            guard let fixedFolder = fetchReadOnlyTopLevelFolder(withFolderType: .bookmark) else {
                throw BookmarksDatabaseError.couldNotFixBookmarkFolder
            }
            self.cachedReadOnlyTopLevelBookmarksFolder = fixedFolder
            return
        }
        self.cachedReadOnlyTopLevelBookmarksFolder = folder
    }

    internal func cacheReadOnlyTopLevelFavoritesFolder() throws {
        guard let folder = fetchReadOnlyTopLevelFolder(withFolderType: .favorite) else {
            try fixFolderDataStructure(withFolderType: .favorite)

            guard let fixedFolder = fetchReadOnlyTopLevelFolder(withFolderType: .favorite) else {
                throw BookmarksDatabaseError.couldNotFixFavoriteFolder
            }
            self.cachedReadOnlyTopLevelFavoritesFolder = fixedFolder
            return
        }
        self.cachedReadOnlyTopLevelFavoritesFolder = folder
    }

}

// MARK: Constants
extension LegacyBookmarksCoreDataStorage {
    enum Constants {
        static let privateContextName = "EditBookmarksAndFolders"
        static let viewContextName = "ViewBookmarksAndFolders"

        static let bookmarkClassName = "BookmarkManagedObject"
        static let folderClassName = "BookmarkFolderManagedObject"

        static let databaseName = "BookmarksAndFolders"
    }
}

// MARK: - CoreData structure fixer
// https://app.asana.com/0/414709148257752/1202779945035904/f
// This is a temporary workaround, do not use the following functions for anything else

extension LegacyBookmarksCoreDataStorage {

    private func deleteExtraOrphanedFolders(_ orphanedFolders: [BookmarkFolderManagedObject],
                                            onContext context: NSManagedObjectContext,
                                            withFolderType folderType: TopLevelFolderType) {
        // Sort all orphaned folders by number of children
        let sorted = orphanedFolders.sorted { ($0.children?.count ?? 0) > ($1.children?.count ?? 0) }

        // Get the folder with the highest number of children
        let folderWithMoreChildren = sorted.first

        // Separate the other folders
        let otherFolders = sorted.suffix(from: 1)

        // Move all children from other folders to the one with highest count and delete the folder
        otherFolders.forEach { folder in
            if let children = folder.children {
                folderWithMoreChildren?.addToChildren(children)
                folder.children = nil
            }
            context.delete(folder)
        }
    }

    /*
     Top level (orphaned) folders need to match its type
     i.e: Favorites and Bookmarks each have their own root folder
     */
    private func createMissingTopLevelFolder(onContext context: NSManagedObjectContext,
                                             withFolderType folderType: TopLevelFolderType) throws {

        // Get all bookmarks
        let bookmarksFetchRequest = NSFetchRequest<BookmarkManagedObject>(entityName: Constants.bookmarkClassName)
        bookmarksFetchRequest.predicate = NSPredicate(format: " %K == %@",
                                                      #keyPath(BookmarkManagedObject.isFavorite),
                                                      NSNumber(value: folderType == .favorite))
        bookmarksFetchRequest.returnsObjectsAsFaults = false

        let bookmarks = try? context.fetch(bookmarksFetchRequest)

        // Create root folder for the specified folder type
        let bookmarksFolder: BookmarkFolderManagedObject
        if folderType == .favorite {
            bookmarksFolder = try Self.rootFavoritesFolderManagedObject(context)
        } else {
            bookmarksFolder = try Self.rootFolderManagedObject(context)
        }

        // Assign all bookmarks to the parent folder
        bookmarks?.forEach {
            $0.parent = bookmarksFolder
        }
    }

    internal func fixFolderDataStructure(withFolderType folderType: TopLevelFolderType) throws {
        let privateContext = getTemporaryPrivateContext()

        var thrownError: Error?
        privateContext.performAndWait {
            do {
                let fetchRequest = NSFetchRequest<BookmarkFolderManagedObject>(entityName: Constants.folderClassName)
                fetchRequest.predicate = NSPredicate(format: "%K == nil AND %K == %@",
                                                     #keyPath(BookmarkManagedObject.parent),
                                                     #keyPath(BookmarkManagedObject.isFavorite),
                                                     NSNumber(value: folderType == .favorite))

                let results = try? privateContext.fetch(fetchRequest)

                if let orphanedFolders = results, orphanedFolders.count > 1 {
                    deleteExtraOrphanedFolders(orphanedFolders, onContext: privateContext, withFolderType: folderType)
                } else {
                    try createMissingTopLevelFolder(onContext: privateContext, withFolderType: folderType)
                }

                do {
                    try privateContext.save()
                } catch {
                    DailyPixel.fireDailyAndCount(pixel: .debugBookmarksTopFolderSaveFailed)
                    assertionFailure("Failure saving bookmark top folder fix")
                }
            } catch {
                thrownError = error
            }
        }
        
        if let thrownError = thrownError {
            throw thrownError
        }
    }
}
