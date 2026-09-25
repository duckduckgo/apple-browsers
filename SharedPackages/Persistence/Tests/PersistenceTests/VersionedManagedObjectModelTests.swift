//
//  VersionedManagedObjectModelTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import CoreData
import XCTest
@testable import Persistence

final class VersionedManagedObjectModelTests: XCTestCase {

    private var location: URL!

    override func setUp() {
        super.setUp()
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: location)
        location = nil
        super.tearDown()
    }

    // MARK: - Model building

    func testWhenModelIsBuiltThenRelationshipsIndexesAndConstraintsAreResolved() throws {
        let model = NSManagedObjectModel(entities: Schema.v2())

        let folder = try XCTUnwrap(model.entitiesByName["Folder"])
        let note = try XCTUnwrap(model.entitiesByName["Note"])
        let notes = try XCTUnwrap(folder.relationshipsByName["notes"])
        let noteFolder = try XCTUnwrap(note.relationshipsByName["folder"])

        XCTAssertEqual(notes.destinationEntity, note)
        XCTAssertEqual(notes.inverseRelationship, noteFolder)
        XCTAssertTrue(notes.isToMany)
        XCTAssertEqual(noteFolder.maxCount, 1)
        XCTAssertEqual(note.indexes.map(\.name), ["byCreated"])
        XCTAssertEqual(note.indexes.first?.elements.first?.property, note.attributesByName["created"])
        XCTAssertEqual(note.uniquenessConstraints as? [[String]], [["identifier"]])
        XCTAssertEqual(note.managedObjectClassName, "NSManagedObject")
        XCTAssertEqual(note.attributesByName["pinned"]?.defaultValue as? Bool, false)
    }

    func testWhenModelDoesNotBindClassesThenEntityVersionHashesAreUnchanged() {
        var entities = Schema.v2()
        entities.modify("Note") { $0.className = "SomeSubclass" }

        let bound = NSManagedObjectModel(entities: entities)
        let unbound = NSManagedObjectModel(entities: entities, bindsClasses: false)

        XCTAssertEqual(bound.entitiesByName["Note"]?.managedObjectClassName, "SomeSubclass")
        XCTAssertEqual(unbound.entitiesByName["Note"]?.managedObjectClassName, "NSManagedObject")
        XCTAssertEqual(bound.entityVersionHashesByName, unbound.entityVersionHashesByName)
    }

    // MARK: - Migration

    func testWhenStoreWasCreatedWithOlderVersionThenLoadingMigratesIt() throws {
        try makeStore(entities: Schema.v1()) { context in
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
            note.setValue("n1", forKey: "identifier")
            note.setValue("Hello", forKey: "text")
            note.setValue(Date(timeIntervalSince1970: 100), forKey: "created")
        }

        let context = try loadStore(model: VersionedManagedObjectModel(versions: [Schema.v1, Schema.v2]))

        try context.performAndWait {
            let notes = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Note"))
            XCTAssertEqual(notes.count, 1)
            XCTAssertEqual(notes.first?.value(forKey: "identifier") as? String, "n1")
            // Renamed from `text` through its renaming identifier.
            XCTAssertEqual(notes.first?.value(forKey: "body") as? String, "Hello")
            XCTAssertEqual(notes.first?.value(forKey: "pinned") as? Bool, false)
            XCTAssertNil(notes.first?.value(forKey: "folder"))
        }
    }

    func testWhenStoreMatchesCurrentVersionThenItIsLoadedAsIs() throws {
        try makeStore(entities: Schema.v2()) { context in
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
            note.setValue("n1", forKey: "identifier")
            note.setValue(Date(timeIntervalSince1970: 100), forKey: "created")
            note.setValue(true, forKey: "pinned")
        }

        let context = try loadStore(model: VersionedManagedObjectModel(versions: [Schema.v1, Schema.v2]))

        try context.performAndWait {
            let notes = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Note"))
            XCTAssertEqual(notes.first?.value(forKey: "pinned") as? Bool, true)
        }
    }

    func testWhenStoreMatchesNoKnownVersionThenCoreDataMigratesItFromTheModelCachedInTheStore() throws {
        try makeStore(entities: Schema.v1()) { context in
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
            note.setValue("n1", forKey: "identifier")
            note.setValue("Hello", forKey: "text")
            note.setValue(Date(timeIntervalSince1970: 100), forKey: "created")
        }

        let context = try loadStore(model: VersionedManagedObjectModel(versions: [Schema.v2]))

        try context.performAndWait {
            let notes = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Note"))
            XCTAssertEqual(notes.first?.value(forKey: "body") as? String, "Hello")
        }
    }

    func testWhenStoreIsMigratedThenNoTemporaryFilesAreLeftBehind() throws {
        try makeStore(entities: Schema.v1()) { _ in }

        _ = try loadStore(model: VersionedManagedObjectModel(versions: [Schema.v1, Schema.v2]))

        let files = try FileManager.default.contentsOfDirectory(atPath: location.path)
        XCTAssertEqual(files.filter { $0.contains("migrated") }, [])
    }

    func testWhenThereIsNoStoreThenItIsCreatedWithCurrentVersion() throws {
        let model = VersionedManagedObjectModel(versions: [Schema.v1, Schema.v2])

        _ = try loadStore(model: model)

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)
        XCTAssertTrue(model.current.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
    }

    // MARK: - Helpers

    private var storeURL: URL {
        location.appendingPathComponent("Test.sqlite")
    }

    private func makeStore(entities: [CoreDataEntity], populate: (NSManagedObjectContext) -> Void) throws {
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel(entities: entities))
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            populate(context)
            try context.save()
        }
        try coordinator.remove(store)
    }

    private func loadStore(model: VersionedManagedObjectModel) throws -> NSManagedObjectContext {
        let database = CoreDataDatabase(name: "Test", containerLocation: location, model: model)
        var result: Result<NSManagedObjectContext, Error>?
        database.loadStore { context, error in
            if let context {
                result = .success(context)
            } else {
                result = .failure(error ?? CocoaError(.coreData))
            }
        }
        return try XCTUnwrap(result).get()
    }
}

private enum Schema {

    static func v1() -> [CoreDataEntity] {
        [
            CoreDataEntity("Note", className: nil, attributes: [
                CoreDataAttribute("identifier", .stringAttributeType),
                CoreDataAttribute("text", .stringAttributeType, optional: true),
                CoreDataAttribute("created", .dateAttributeType),
            ], uniquenessConstraints: [["identifier"]]),
        ]
    }

    /// Renames `text` to `body`, adds `pinned` and a `Folder` entity.
    static func v2() -> [CoreDataEntity] {
        var entities = v1()
        entities.modify("Note") { note in
            note.attributes.removeAll { $0.name == "text" }
            note.attributes.append(CoreDataAttribute("body", .stringAttributeType, optional: true, renamingIdentifier: "text"))
            note.attributes.append(CoreDataAttribute("pinned", .booleanAttributeType, defaultValue: false))
            note.relationships.append(.toOne("folder", "Folder", inverse: "notes", optional: true))
            note.indexes.append(CoreDataIndex("byCreated", properties: ["created"]))
        }
        entities.append(CoreDataEntity("Folder", className: nil, attributes: [
            CoreDataAttribute("name", .stringAttributeType),
        ], relationships: [
            .toMany("notes", "Note", inverse: "folder", optional: true, deleteRule: .cascadeDeleteRule),
        ]))
        return entities
    }
}
