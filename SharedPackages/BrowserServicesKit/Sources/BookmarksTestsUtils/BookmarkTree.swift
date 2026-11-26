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

public struct ModifiedAtConstraint: Sendable {
    let check: @Sendable (Date?) -> Void

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

public enum BookmarkTreeNode: Sendable {
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

public struct BookmarkTree: Sendable {

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

// Read managed objects on their context queue, including relationships that can fire faults.
private struct BookmarkSnapshot: Sendable {
    let uuid: String?
    let title: String?
    let url: String?
    let isStub: Bool
    let isFolder: Bool
    let isPendingDeletion: Bool
    let visibleChildCount: Int
    let childCount: Int?
    let favoritedOn: Set<FavoritesFolderID>
    let modifiedAt: Date?
    let lastChildrenArrayReceivedFromSync: [String]?

    init(_ entity: BookmarkEntity) {
        uuid = entity.uuid
        title = entity.title
        url = entity.url
        isStub = entity.isStub
        isFolder = entity.isFolder
        isPendingDeletion = entity.isPendingDeletion
        visibleChildCount = entity.childrenArray.count
        childCount = entity.children?.count
        favoritedOn = Set(entity.favoritedOn)
        modifiedAt = entity.modifiedAt
        lastChildrenArrayReceivedFromSync = entity.lastChildrenArrayReceivedFromSync
    }

    static func subtree(_ root: BookmarkEntity) -> [Self] {
        var result = [Self]()
        var queue = [root]
        var visited = Set<NSManagedObjectID>()
        var index = 0
        while index < queue.count {
            let entity = queue[index]
            index += 1
            guard visited.insert(entity.objectID).inserted else {
                XCTFail("Cycle in bookmark tree at \(entity.uuid ?? "<no UUID>")")
                break
            }
            result.append(Self(entity))
            if entity.isFolder, let children = entity.children?.array as? [BookmarkEntity] {
                queue.append(contentsOf: children)
            }
        }
        return result
    }
}

public extension XCTestCase {
    func assertEquivalent(withTimestamps: Bool = true, withLastChildrenArrayReceivedFromSync: Bool = true, _ bookmarkEntity: BookmarkEntity, _ tree: BookmarkTree, file: StaticString = #file, line: UInt = #line) {
        guard let sourceContext = bookmarkEntity.managedObjectContext else {
            XCTFail("The bookmark must belong to a managed object context", file: file, line: line)
            return
        }
        let rootID = bookmarkEntity.objectID
        let actualRoot = sourceContext.performAndWait {
            let root = sourceContext.registeredObject(for: rootID) as? BookmarkEntity
            return root.map(BookmarkSnapshot.subtree)
        }
        guard let actualRoot else {
            XCTFail("The root bookmark must be registered in its context", file: file, line: line)
            return
        }

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = sourceContext.persistentStoreCoordinator

        let orphansContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        orphansContext.persistentStoreCoordinator = sourceContext.persistentStoreCoordinator

        let actualOrphans = orphansContext.performAndWait {
            BookmarkUtils.fetchOrphanedEntities(orphansContext).map(BookmarkSnapshot.subtree)
        }
        let (expectedTrees, constraints) = context.performAndWait {
            context.deleteAll(matching: BookmarkEntity.fetchRequest())
            BookmarkUtils.prepareFoldersStructure(in: context)
            let (root, orphans, constraints) = tree.createEntitiesForCheckingModifiedAt(in: context)
            return (([root] + orphans).map(BookmarkSnapshot.subtree), constraints)
        }

        let actualTrees = [actualRoot] + actualOrphans
        XCTAssertEqual(actualOrphans.map { $0.first?.uuid }, expectedTrees.dropFirst().map { $0.first?.uuid },
                       "orphan bookmark IDs mismatch", file: file, line: line)
        for (expected, actual) in zip(expectedTrees, actualTrees) {
            XCTAssertEqual(expected.count, actual.count, "node count mismatch", file: file, line: line)
            for (expectedNode, thisNode) in zip(expected, actual) {
                let thisUUID = thisNode.uuid ?? "<no local UUID>"
                XCTAssertEqual(expectedNode.uuid, thisNode.uuid, "uuid mismatch", file: file, line: line)
                XCTAssertEqual(expectedNode.title, thisNode.title, "title mismatch for \(thisUUID)", file: file, line: line)
                XCTAssertEqual(expectedNode.url, thisNode.url, "url mismatch for \(thisUUID)", file: file, line: line)
                XCTAssertEqual(expectedNode.isStub, thisNode.isStub, "stub mismatch for \(thisUUID)", file: file, line: line)
                XCTAssertEqual(expectedNode.isFolder, thisNode.isFolder, "isFolder mismatch for \(thisUUID)", file: file, line: line)
                XCTAssertEqual(expectedNode.isPendingDeletion, thisNode.isPendingDeletion, "isPendingDeletion mismatch for \(thisUUID)", file: file, line: line)
                XCTAssertEqual(expectedNode.visibleChildCount, thisNode.visibleChildCount, "children count mismatch for \(thisUUID)", file: file, line: line)
                XCTAssertEqual(expectedNode.favoritedOn, thisNode.favoritedOn, "favoritedOn mismatch for \(thisUUID)", file: file, line: line)
                if withTimestamps {
                    if let constraint = constraints[thisUUID] {
                        constraint.check(thisNode.modifiedAt)
                    } else {
                        XCTAssertEqual(expectedNode.modifiedAt, thisNode.modifiedAt, "modifiedAt mismatch for \(thisUUID)", file: file, line: line)
                    }
                }
                if expectedNode.isFolder {
                    XCTAssertEqual(expectedNode.childCount, thisNode.childCount, "children count mismatch for \(thisUUID)", file: file, line: line)
                    if withLastChildrenArrayReceivedFromSync {
                        XCTAssertEqual(expectedNode.lastChildrenArrayReceivedFromSync, thisNode.lastChildrenArrayReceivedFromSync, "lastChildrenArrayReceivedFromSync mismatch for \(thisUUID)", file: file, line: line)
                    }
                }
            }
        }
    }
}
