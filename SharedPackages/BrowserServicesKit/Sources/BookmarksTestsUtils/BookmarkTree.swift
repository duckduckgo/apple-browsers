//
//  BookmarkTree.swift
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

import Bookmarks
import CoreData
import Foundation
import XCTest

public struct ModifiedAtConstraint {
    var check: (Date?) -> Void

    public static func `nil`(file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { date in
            XCTAssertNil(date, file: file, line: line)
        }
    }

    public static func notNil(file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { date in
            XCTAssertNotNil(date, file: file, line: line)
        }
    }

    public static func greaterThan(_ date: Date, file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { actualDate in
            guard let actualDate = actualDate else {
                XCTFail("Date is nil", file: file, line: line)
                return
            }
            XCTAssertGreaterThan(actualDate, date, file: file, line: line)
        }
    }

    public static func lessThan(_ date: Date, file: StaticString = #file, line: UInt = #line) -> ModifiedAtConstraint {
        ModifiedAtConstraint { actualDate in
            guard let actualDate = actualDate else {
                XCTFail("Date is nil", file: file, line: line)
                return
            }
            XCTAssertLessThan(actualDate, date, file: file, line: line)
        }
    }
}

public enum BookmarkTreeNode {
    case bookmark(id: String, name: String?, url: String?, favoritedOn: [FavoritesFolderID], modifiedAt: Date?, isDeleted: Bool, isStub: Bool, isOrphaned: Bool, modifiedAtConstraint: ModifiedAtConstraint?)
    case folder(id: String, name: String?, children: [BookmarkTreeNode], modifiedAt: Date?, isDeleted: Bool, isStub: Bool, isOrphaned: Bool, lastChildrenArrayReceivedFromSync: [String]?, modifiedAtConstraint: ModifiedAtConstraint?)

    public var id: String {
        switch self {
        case .bookmark(let id, _, _, _, _, _, _, _, _):
            return id
        case .folder(let id, _, _, _, _, _, _, _, _):
            return id
        }
    }

    public var name: String? {
        switch self {
        case .bookmark(_, let name, _, _, _, _, _, _, _):
            return name
        case .folder(_, let name, _, _, _, _, _, _, _):
            return name
        }
    }

    public var modifiedAt: Date? {
        switch self {
        case .bookmark(_, _, _, _, let modifiedAt, _, _, _, _):
            return modifiedAt
        case .folder(_, _, _, let modifiedAt, _, _, _, _, _):
            return modifiedAt
        }
    }

    public var isDeleted: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, let isDeleted, _, _, _):
            return isDeleted
        case .folder(_, _, _, _, let isDeleted, _, _, _, _):
            return isDeleted
        }
    }

    public var isStub: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, _, let isStub, _, _):
            return isStub
        case .folder(_, _, _, _, _, let isStub, _, _, _):
            return isStub
        }
    }

    public var isOrphaned: Bool {
        switch self {
        case .bookmark(_, _, _, _, _, _, _, let isOrphaned, _):
            return isOrphaned
        case .folder(_, _, _, _, _, _, let isOrphaned, _, _):
            return isOrphaned
        }
    }

    public var lastChildrenArrayReceivedFromSync: [String]? {
        switch self {
        case .bookmark:
            return nil
        case .folder(_, _, _, _, _, _, _, let lastChildrenArrayReceivedFromSync, _):
            return lastChildrenArrayReceivedFromSync
        }
    }

    public var modifiedAtConstraint: ModifiedAtConstraint? {
        switch self {
        case .bookmark(_, _, _, _, _, _, _, _, let modifiedAtConstraint):
            return modifiedAtConstraint
        case .folder(_, _, _, _, _, _, _, _, let modifiedAtConstraint):
            return modifiedAtConstraint
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
    var isStub: Bool
    var isOrphaned: Bool
    var modifiedAtConstraint: ModifiedAtConstraint?

    public init(_ name: String? = nil, id: String? = nil, url: String? = nil, favoritedOn: [FavoritesFolderID] = [], modifiedAt: Date? = nil, isDeleted: Bool = false, isStub: Bool = false, isOrphaned: Bool = false, modifiedAtConstraint: ModifiedAtConstraint? = nil) {
        self.id = id ?? UUID().uuidString
        if isStub {
            self.name = nil
            self.url = nil
        } else {
            self.name = name ?? id
            self.url = (url ?? name) ?? id
        }
        self.favoritedOn = favoritedOn
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isStub = isStub
        self.modifiedAtConstraint = modifiedAtConstraint
        self.isOrphaned = isOrphaned
    }

    public func asBookmarkTreeNode() -> BookmarkTreeNode {
        .bookmark(id: id, name: name, url: url, favoritedOn: favoritedOn, modifiedAt: modifiedAt, isDeleted: isDeleted, isStub: isStub, isOrphaned: isOrphaned, modifiedAtConstraint: modifiedAtConstraint)
    }
}

public struct Folder: BookmarkTreeNodeConvertible {
    var id: String
    var name: String?
    var modifiedAt: Date?
    var isDeleted: Bool
    var isStub: Bool
    var isOrphaned: Bool
    var modifiedAtConstraint: ModifiedAtConstraint?
    var lastChildrenArrayReceivedFromSync: [String]?
    var children: [BookmarkTreeNode]

    public init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isStub: Bool = false, isOrphaned: Bool = false, lastChildrenArrayReceivedFromSync: [String]? = nil, @BookmarkTreeBuilder children: () -> [BookmarkTreeNode] = { [] }) {
        self.init(name, id: id, modifiedAt: modifiedAt, isDeleted: isDeleted, isStub: isStub, isOrphaned: isOrphaned, modifiedAtConstraint: nil, lastChildrenArrayReceivedFromSync: lastChildrenArrayReceivedFromSync, children: children)
    }

    public init(_ name: String? = nil, id: String? = nil, modifiedAt: Date? = nil, isDeleted: Bool = false, isStub: Bool = false, isOrphaned: Bool = false, modifiedAtConstraint: ModifiedAtConstraint? = nil, lastChildrenArrayReceivedFromSync: [String]? = nil, @BookmarkTreeBuilder children: () -> [BookmarkTreeNode] = { [] }) {
        self.id = id ?? UUID().uuidString
        self.name = name ?? id
        self.modifiedAt = modifiedAt
        self.isDeleted = isDeleted
        self.isOrphaned = isOrphaned
        self.isStub = isStub
        self.lastChildrenArrayReceivedFromSync = lastChildrenArrayReceivedFromSync
        self.modifiedAtConstraint = modifiedAtConstraint
        self.children = children()
    }

    public func asBookmarkTreeNode() -> BookmarkTreeNode {
        .folder(id: id, name: name, children: children, modifiedAt: modifiedAt, isDeleted: isDeleted, isStub: isStub, isOrphaned: isOrphaned, lastChildrenArrayReceivedFromSync: lastChildrenArrayReceivedFromSync, modifiedAtConstraint: modifiedAtConstraint)
    }
}

@resultBuilder
public struct BookmarkTreeBuilder {

    public static func buildBlock(_ components: BookmarkTreeNodeConvertible...) -> [BookmarkTreeNode] {
        components.compactMap { $0.asBookmarkTreeNode() }
    }
}

public struct BookmarkTree {

    public init(modifiedAt: Date? = nil, modifiedAtConstraint: ModifiedAtConstraint? = nil, lastChildrenArrayReceivedFromSync: [String]? = nil, @BookmarkTreeBuilder builder: () -> [BookmarkTreeNode]) {
        self.modifiedAt = modifiedAt
        self.modifiedAtConstraint = modifiedAtConstraint
        self.lastChildrenArrayReceivedFromSync = lastChildrenArrayReceivedFromSync
        self.bookmarkTreeNodes = builder()
    }

    @discardableResult
    public func createEntities(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity]) {
        let (rootFolder, orphans, _) = createEntitiesForCheckingModifiedAt(in: context)
        return (rootFolder, orphans)
    }

    @discardableResult
    public func createEntitiesForCheckingModifiedAt(in context: NSManagedObjectContext) -> (BookmarkEntity, [BookmarkEntity], [String: ModifiedAtConstraint]) {
        let rootFolder = BookmarkUtils.fetchRootFolder(context)!
        rootFolder.modifiedAt = modifiedAt
        if let lastChildrenArrayReceivedFromSync {
            rootFolder.lastChildrenArrayReceivedFromSync = lastChildrenArrayReceivedFromSync
        }
        let favoritesFolders = BookmarkUtils.fetchFavoritesFolders(withUUIDs: Set(FavoritesFolderID.allCases.map(\.rawValue)), in: context)
        var orphans = [BookmarkEntity]()
        var modifiedAtConstraints = [String: ModifiedAtConstraint]()
        if let modifiedAtConstraint {
            modifiedAtConstraints[BookmarkEntity.Constants.rootFolderID] = modifiedAtConstraint
        }
        for bookmarkTreeNode in bookmarkTreeNodes {
            let (entity, checks) = BookmarkEntity.makeWithModifiedAtConstraints(with: bookmarkTreeNode, rootFolder: rootFolder, favoritesFolders: favoritesFolders, in: context)
            if bookmarkTreeNode.isOrphaned {
                orphans.append(entity)
            }
            modifiedAtConstraints.merge(checks) { (_, rhs) in
                assertionFailure("duplicate keys found")
                return rhs
            }
        }
        return (rootFolder, orphans, modifiedAtConstraints)
    }

    let modifiedAt: Date?
    let lastChildrenArrayReceivedFromSync: [String]?
    let modifiedAtConstraint: ModifiedAtConstraint?
    let bookmarkTreeNodes: [BookmarkTreeNode]
}

public extension BookmarkEntity {
    @discardableResult
    static func make(with treeNode: BookmarkTreeNode,
                     rootFolder: BookmarkEntity,
                     favoritesFolders: [BookmarkEntity],
                     in context: NSManagedObjectContext) -> BookmarkEntity {
        makeWithModifiedAtConstraints(with: treeNode, rootFolder: rootFolder, favoritesFolders: favoritesFolders, in: context).0
    }

    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity
    static func makeWithModifiedAtConstraints(with treeNode: BookmarkTreeNode,
                                              rootFolder: BookmarkEntity,
                                              favoritesFolders: [BookmarkEntity],
                                              in context: NSManagedObjectContext) -> (BookmarkEntity, [String: ModifiedAtConstraint]) {
        var entity: BookmarkEntity!

        var queues: [[BookmarkTreeNode]] = [[treeNode]]
        var parents: [BookmarkEntity] = [rootFolder]
        var modifiedAtConstraints = [String: ModifiedAtConstraint]()

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parent = parents.removeFirst()

            while !queue.isEmpty {
                let node = queue.removeFirst()

                switch node {
                case .bookmark(let id, let name, let url, let favoritedOn, let modifiedAt, let isDeleted, let isStub, let isOrphaned, let modifiedAtConstraint):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = false
                    bookmarkEntity.title = name
                    bookmarkEntity.url = url
                    bookmarkEntity.isStub = isStub
                    bookmarkEntity.modifiedAt = modifiedAt
                    modifiedAtConstraints[id] = modifiedAtConstraint

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
                case .folder(let id, let name, let children, let modifiedAt, let isDeleted, let isStub, let isOrphaned, let lastChildrenArrayReceivedFromSync, let modifiedAtConstraint):
                    let bookmarkEntity = BookmarkEntity(context: context)
                    if entity == nil {
                        entity = bookmarkEntity
                    }
                    bookmarkEntity.uuid = id
                    bookmarkEntity.isFolder = true
                    bookmarkEntity.title = name
                    bookmarkEntity.isStub = isStub
                    bookmarkEntity.modifiedAt = modifiedAt
                    modifiedAtConstraints[id] = modifiedAtConstraint
                    if isDeleted {
                        bookmarkEntity.markPendingDeletion()
                    }
                    if !isOrphaned {
                        bookmarkEntity.parent = parent
                    }
                    if let lastChildrenArrayReceivedFromSync {
                        bookmarkEntity.lastChildrenArrayReceivedFromSync = lastChildrenArrayReceivedFromSync
                    }
                    parents.append(bookmarkEntity)
                    queues.append(children)
                }
            }
        }

        return (entity, modifiedAtConstraints)
    }
}

public extension XCTestCase {
    func assertEquivalent(withTimestamps: Bool = true, withLastChildrenArrayReceivedFromSync: Bool = true, _ bookmarkEntity: BookmarkEntity, _ tree: BookmarkTree, file: StaticString = #file, line: UInt = #line) {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = bookmarkEntity.managedObjectContext?.persistentStoreCoordinator

        let orphansContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        orphansContext.persistentStoreCoordinator = bookmarkEntity.managedObjectContext?.persistentStoreCoordinator

        var orphans: [BookmarkEntity] = []
        var expectedRootFolder: BookmarkEntity! = nil
        var expectedOrphans: [BookmarkEntity] = []
        var modifiedAtConstraints: [String: ModifiedAtConstraint] = [:]

        orphansContext.performAndWait {
            orphans = BookmarkUtils.fetchOrphanedEntities(orphansContext)
        }

        context.performAndWait {
            context.deleteAll(matching: BookmarkEntity.fetchRequest())
            BookmarkUtils.prepareFoldersStructure(in: context)
            (expectedRootFolder, expectedOrphans, modifiedAtConstraints) = tree.createEntitiesForCheckingModifiedAt(in: context)
        }

        let thisFolder = bookmarkEntity
        XCTAssertEqual(expectedRootFolder.uuid, thisFolder.uuid, "root folder uuid mismatch", file: file, line: line)
        if withLastChildrenArrayReceivedFromSync {
            XCTAssertEqual(expectedRootFolder.lastChildrenArrayReceivedFromSync, thisFolder.lastChildrenArrayReceivedFromSync, "root folder lastChildrenArrayReceivedFromSync mismatch", file: file, line: line)
        }

        var expectedTreeQueue: [BookmarkEntity] = [[expectedRootFolder], expectedOrphans].flatMap { $0 }
        var thisTreeQueue: [BookmarkEntity] = [[thisFolder], orphans].flatMap { $0 }

        while !expectedTreeQueue.isEmpty {
            guard !thisTreeQueue.isEmpty else {
                XCTFail("No more children in the tree, while \(expectedTreeQueue.count) (ids: \(expectedTreeQueue.compactMap(\.uuid))) still expected", file: file, line: line)
                return
            }
            let expectedNode = expectedTreeQueue.removeFirst()
            let thisNode = thisTreeQueue.removeFirst()

            let thisUUID = thisNode.uuid ?? "<no local UUID>"

            XCTAssertEqual(expectedNode.uuid, thisNode.uuid, "uuid mismatch", file: file, line: line)
            XCTAssertEqual(expectedNode.title, thisNode.title, "title mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.url, thisNode.url, "url mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.isStub, thisNode.isStub, "stub mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.isFolder, thisNode.isFolder, "isFolder mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.isPendingDeletion, thisNode.isPendingDeletion, "isPendingDeletion mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(expectedNode.childrenArray.count, thisNode.childrenArray.count, "children count mismatch for \(thisUUID)", file: file, line: line)
            XCTAssertEqual(Set(expectedNode.favoritedOn), Set(thisNode.favoritedOn), "favoritedOn mismatch for \(thisUUID)", file: file, line: line)
            if withTimestamps {
                if let modifiedAtConstraint = modifiedAtConstraints[thisUUID] {
                    modifiedAtConstraint.check(thisNode.modifiedAt)
                } else {
                    XCTAssertEqual(expectedNode.modifiedAt, thisNode.modifiedAt, "modifiedAt mismatch for \(thisUUID)", file: file, line: line)
                }
            }

            if expectedNode.isFolder {
                if withLastChildrenArrayReceivedFromSync {
                    XCTAssertEqual(expectedNode.lastChildrenArrayReceivedFromSync, thisNode.lastChildrenArrayReceivedFromSync, "lastChildrenArrayReceivedFromSync mismatch for \(thisUUID)", file: file, line: line)
                }
                XCTAssertEqual(expectedNode.children?.count, thisNode.children?.count, "children count mismatch for \(thisUUID)", file: file, line: line)
                expectedTreeQueue.append(contentsOf: (expectedNode.children?.array as? [BookmarkEntity]) ?? [])
                thisTreeQueue.append(contentsOf: (thisNode.children?.array as? [BookmarkEntity]) ?? [])
            }
        }
    }
}
