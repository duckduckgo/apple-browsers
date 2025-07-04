//
//  BookmarksTestDBBuilder.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Bookmarks

// swiftlint:disable force_try

@main
struct BookmarksTestDBBuilder {

    static func main() {
        generateDatabase(modelVersion: 5)
    }

    private static func generateDatabase(modelVersion: Int) {
        let bundle = Bookmarks.bundle
        var momUrl: URL?
        if modelVersion == 1 {
            momUrl = bundle.url(forResource: "BookmarksModel.momd/BookmarksModel", withExtension: "mom")
        } else {
            momUrl = bundle.url(forResource: "BookmarksModel.momd/BookmarksModel \(modelVersion)", withExtension: "mom")
        }

        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
           fatalError("Could not find directory")
        }

        let model = NSManagedObjectModel(contentsOf: momUrl!)
        let stack = CoreDataDatabase(name: "Bookmarks_V\(modelVersion)",
                                     containerLocation: dir,
                                     model: model!)
        stack.loadStore()

        let context = stack.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            buildTestTree(in: context)
        }
    }

    private static func buildTestTree(in context: NSManagedObjectContext) {
        /* When modifying, please add requirements to list below
             - Test roof folders (root, favorites) migration and order.
             - Test regular folder migration and order.
             - Test Form Factor favorites.
         */
        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.unified, .mobile])
            Folder(id: "3") {
                Folder(id: "31") {}
                Bookmark(id: "32", favoritedOn: [.unified, .desktop])
                Bookmark(id: "33", favoritedOn: [.unified, .desktop, .mobile])
            }
            Bookmark(id: "4", favoritedOn: [.unified, .desktop, .mobile])
            Bookmark(id: "5", favoritedOn: [.unified, .desktop])
        }

        bookmarkTree.createEntities(in: context)

        // Apply order to make sure order of generation (or PK) does not influence order of results
        let unifiedRoot = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue,
                                                             in: context)!
        reorderFavorites(to: ["5", "4", "33", "32", "2"], favoritesRoot: unifiedRoot)

        if let desktopRoot = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.desktop.rawValue,
                                                                in: context) {
            reorderFavorites(to: ["32", "4", "33", "5"], favoritesRoot: desktopRoot)
        }

        if let mobileRoot = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.mobile.rawValue,
                                                               in: context) {
            reorderFavorites(to: ["4", "2", "33"], favoritesRoot: mobileRoot)
        }

        try! context.save()
    }

    static func reorderFavorites(to ids: [String], favoritesRoot: BookmarkEntity) {
        let favs = favoritesRoot.favoritesArray
        for fav in favs {
            fav.removeFromFavorites(favoritesRoot: favoritesRoot)
        }

        for id in ids {
            let fav = favs.first(where: { $0.uuid == id })
            fav?.addToFavorites(favoritesRoot: favoritesRoot)
        }
    }
}

public enum BookmarkTreeNode {
    case bookmark(id: String, name: String?, url: String?, favoritedOn: [FavoritesFolderID], modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool)
    case folder(id: String, name: String?, children: [BookmarkTreeNode], modifiedAt: Date?, isDeleted: Bool, isOrphaned: Bool)

    public var id: String {
        switch self {
        case .bookmark(let id, _, _, _, _, _, _):
            return id
        case .folder(let id, _, _, _, _, _):
            return id
        }
    }

    public var name: String? {
        switch self {
        case .bookmark(_, let name, _, _, _, _, _):
            return name
        case .folder(_, let name, _, _, _, _):
            return name
        }
    }

    public var modifiedAt: Date? {
        switch self {
        case .bookmark(_, _, _, _, let modifiedAt, _, _):
            return modifiedAt
        case .folder(_, _, _, let modifiedAt, _, _):
            return modifiedAt
        }
    }

    public var isDeleted: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, let isDeleted, _):
            return isDeleted
        case .folder(_, _, _, _, let isDeleted, _):
            return isDeleted
        }
    }

    public var isOrphaned: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, _, let isOrphaned):
            return isOrphaned
        case .folder(_, _, _, _, _, let isOrphaned):
            return isOrphaned
        }
    }
}

public protocol BookmarkTreeNodeConvertible {
    func asBookmarkTreeNode() -> BookmarkTreeNode
}

public struct Bookmark: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var url: String?
    var favoritedOn: [FavoritesFolderID]
    var modifiedAt: Date?
    var isDeleted: Bool
    var isOrphaned: Bool

    public init(_ name: String? = nil, id: String? = nil, url: String? = nil, favoritedOn: [FavoritesFolderID] = [], modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.url = (url ?? name) ?? id
        self.favoritedOn = favoritedOn
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isOrphaned = isOrphaned
    }

    public func asBookmarkTreeNode() -> BookmarkTreeNode {
        .bookmark(id: id, name: name, url: url, favoritedOn: favoritedOn, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned)
    }
}

public struct Folder: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var modifiedAt: Date?
    var isDeleted: Bool
    var isOrphaned: Bool
    var children: [BookmarkTreeNode]

    public init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isOrphaned: Bool = false, @BookmarkTreeBuilder children: () -> [BookmarkTreeNode] = { [] }) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isOrphaned = isOrphaned
        self.children = children()
    }

    public func asBookmarkTreeNode() -> BookmarkTreeNode {
        .folder(id: id, name: name, children: children, modifiedAt: modifiedAt, isDeleted: isDeleted, isOrphaned: isOrphaned)
    }
}

@resultBuilder
public struct BookmarkTreeBuilder {

    public static func buildBlock(_ components: BookmarkTreeNodeConvertible...) -> [BookmarkTreeNode] {
        components.compactMap { $0.asBookmarkTreeNode() }
    }
}

public struct BookmarkTree {

    public init(modifiedAt: Date? = nil, @BookmarkTreeBuilder builder: () -> [BookmarkTreeNode]) {
        self.modifiedAt = modifiedAt
        self.bookmarkTreeNodes = builder()
    }

    @discardableResult
    public func createEntities(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity]) {
        let (rootFolder, orphans) = createEntitiesForCheckingModifiedAt(in: context)
        return (rootFolder, orphans)
    }

    @discardableResult
    public func createEntitiesForCheckingModifiedAt(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity]) {
        try? BookmarkUtils.prepareLegacyFoldersStructure(in: context)

        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        rootFolder.modifiedAt = modifiedAt
        let favoritesFolders = BookmarkUtils.fetchFavoritesFolders(withUUIDs: Set(FavoritesFolderID.allCases.map(\.rawValue)), in: context)
        var orphans = [BookmarkEntity]()
        for bookmarkTreeNode in bookmarkTreeNodes {
            let entity = BookmarkEntity.makeWithModifiedAtConstraints(with: bookmarkTreeNode, rootFolder: rootFolder, favoritesFolders: favoritesFolders, in: context)
            if bookmarkTreeNode.isOrphaned {
                orphans.append(entity)
            }
        }
        return (rootFolder, orphans)
    }

    let modifiedAt: Date?
    let bookmarkTreeNodes: [BookmarkTreeNode]
}

public extension BookmarkEntity {
    @discardableResult
    static func make(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, favoritesFolders: [BookmarkEntity], in context: NSManagedObjectContext) -> BookmarkEntity {
        makeWithModifiedAtConstraints(with: treeNode, rootFolder: rootFolder, favoritesFolders: favoritesFolders, in: context)
    }

    @discardableResult static func makeWithModifiedAtConstraints(with treeNode: BookmarkTreeNode, rootFolder: BookmarkEntity, favoritesFolders: [BookmarkEntity], in context: NSManagedObjectContext) -> BookmarkEntity {
        var entity: BookmarkEntity!

        var queues: [[BookmarkTreeNode]] = [[treeNode]]
        var parents: [BookmarkEntity] = [rootFolder]

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parent = parents.removeFirst()

            while !queue.isEmpty {
                let node = queue.removeFirst()

                switch node {
                case .bookmark(let id, let name, let url, let favoritedOn, let modifiedAt, let isDeleted, let isOrphaned):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = false
                    bookmarkEntity.title = name
                    bookmarkEntity.url = url
                    bookmarkEntity.modifiedAt = modifiedAt

                    for platform in favoritedOn {
                        if let favoritesFolder = favoritesFolders.first(where: { $0.uuid == platform.rawValue }) {
                            bookmarkEntity.addToFavorites(favoritesRoot: favoritesFolder)
                        }
                    }

                    if isDeleted {
                        bookmarkEntity.markPendingDeletion()
                    }
                    if !isOrphaned {
                        bookmarkEntity.parent = parent
                    }
                case .folder(let id, let name, let children, let modifiedAt, let isDeleted, let isOrphaned):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = true
                    bookmarkEntity.title = name
                    bookmarkEntity.modifiedAt = modifiedAt
                    if isDeleted {
                        bookmarkEntity.markPendingDeletion()
                    }
                    if !isOrphaned {
                        bookmarkEntity.parent = parent
                    }
                    parents.append(bookmarkEntity)
                    queues.append(children)
                }
            }
        }

        return entity
    }
}

// swiftlint:enable force_try
