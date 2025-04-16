//
//  BookmarkCoreDataImporter.swift
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
import CoreData
import Persistence
import BrowserServicesKit

public class BookmarkCoreDataImporter {

    let context: NSManagedObjectContext
    let favoritesDisplayMode: FavoritesDisplayMode

    public init(database: CoreDataDatabase, favoritesDisplayMode: FavoritesDisplayMode) {
        self.context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        self.favoritesDisplayMode = favoritesDisplayMode
    }

    public func importBookmarks(_ bookmarks: [BookmarkOrFolder]) async throws -> BookmarksImportSummary {

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BookmarksImportSummary, Error>) in

            context.performAndWait { () in
                do {
                    let favoritesFolders = BookmarkUtils.fetchFavoritesFolders(for: favoritesDisplayMode, in: context)

                    guard let topLevelBookmarksFolder = BookmarkUtils.fetchRootFolder(context) else {
                        throw BookmarksCoreDataError.fetchingExistingItemFailed
                    }

                    var bookmarkURLToIDMap = try bookmarkURLToID(in: context)
                    var summary = BookmarksImportSummary(successful: 0, duplicates: 0, failed: 0)

                    try recursivelyCreateEntities(from: bookmarks,
                                                  parent: topLevelBookmarksFolder,
                                                  favoritesFolders: favoritesFolders,
                                                  bookmarkURLToIDMap: &bookmarkURLToIDMap,
                                                  summary: &summary)
                    try context.save()
                    continuation.resume(returning: summary)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func bookmarkURLToID(in context: NSManagedObjectContext) throws -> [String: NSManagedObjectID] {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "BookmarkEntity")
        fetch.predicate = NSPredicate(
            format: "%K == false && %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        fetch.resultType = .dictionaryResultType

        let idDescription = NSExpressionDescription()
        idDescription.name = "objectID"
        idDescription.expression = NSExpression.expressionForEvaluatedObject()
        idDescription.expressionResultType = .objectIDAttributeType

        fetch.propertiesToFetch = [idDescription, #keyPath(BookmarkEntity.url)]

        let dict = try context.fetch(fetch) as? [[String: Any]]

        if let result = dict?.reduce(into: [String: NSManagedObjectID](), { partialResult, data in
            guard let urlString = data[#keyPath(BookmarkEntity.url)] as? String,
                  let objectID = data["objectID"] as? NSManagedObjectID else { return }

            partialResult[urlString] = objectID
        }) {
            return result
        }
        return [:]
    }

    private func recursivelyCreateEntities(from bookmarks: [BookmarkOrFolder],
                                           parent: BookmarkEntity,
                                           favoritesFolders: [BookmarkEntity],
                                           bookmarkURLToIDMap: inout [String: NSManagedObjectID],
                                           summary: inout BookmarksImportSummary) throws {
        for bookmarkOrFolder in bookmarks {
            if bookmarkOrFolder.isInvalidBookmark {
                summary.failed += 1
                continue
            }

            switch bookmarkOrFolder.type {
            case .folder:
                let folder = BookmarkEntity.makeFolder(title: bookmarkOrFolder.name,
                                                       parent: parent,
                                                       context: context)
                summary.successful += 1
                if let children = bookmarkOrFolder.children {
                    try recursivelyCreateEntities(from: children,
                                                  parent: folder,
                                                  favoritesFolders: favoritesFolders,
                                                  bookmarkURLToIDMap: &bookmarkURLToIDMap,
                                                  summary: &summary)
                }
            case .favorite:
                if let url = bookmarkOrFolder.url {
                    if let objectID = bookmarkURLToIDMap[url.absoluteString],
                       let bookmark = try? context.existingObject(with: objectID) as? BookmarkEntity {
                        bookmark.addToFavorites(folders: favoritesFolders)
                    } else {
                        let newFavorite = BookmarkEntity.makeBookmark(title: bookmarkOrFolder.name,
                                                                      url: url.absoluteString,
                                                                      parent: parent,
                                                                      context: context)
                        newFavorite.addToFavorites(folders: favoritesFolders)
                        bookmarkURLToIDMap[url.absoluteString] = newFavorite.objectID
                    }
                    summary.successful += 1
                } else {
                    summary.failed += 1
                }
            case .bookmark:
                if let url = bookmarkOrFolder.url {
                    if parent.isRoot,
                       parent.childrenArray.first(where: { $0.urlObject == url }) != nil {
                        summary.successful += 1
                        continue
                    } else {
                        let newBookmark = BookmarkEntity.makeBookmark(title: bookmarkOrFolder.name,
                                                                      url: url.absoluteString,
                                                                      parent: parent,
                                                                      context: context)
                        bookmarkURLToIDMap[url.absoluteString] = newBookmark.objectID
                    }
                    summary.successful += 1
                } else {
                    summary.failed += 1
                }
            }
        }
    }

    private func containsBookmark(with url: URL) -> Bool {
        return false
    }
}
