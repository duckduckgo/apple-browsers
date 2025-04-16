//
//  CoreDataErrorsParserTests.swift
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

import XCTest
import CoreData
import Persistence

@objc(TestEntity)
class TestEntity: NSManagedObject {

    static let name = "TestEntity"

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "TestEntity", in: context)!
    }

    @NSManaged public var attribute: String?
    @NSManaged public var relationTo: TestEntity?
    @NSManaged public var relationFrom: TestEntity?
}

class CoreDataErrorsParserTests: XCTestCase {

    func tempDBDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    var db: CoreDataDatabase!

    func testModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "TestEntity"
        entity.managedObjectClassName = TestEntity.name

        var properties = [NSPropertyDescription]()

        let attribute = NSAttributeDescription()
        attribute.name = "attribute"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false
        properties.append(attribute)

        let relationTo = NSRelationshipDescription()
        let relationFrom = NSRelationshipDescription()

        relationTo.name = "relationTo"
        relationFrom.isOptional = false
        relationTo.destinationEntity = entity
        relationTo.minCount = 0
        relationTo.maxCount = 1
        relationTo.deleteRule = .nullifyDeleteRule
        relationTo.inverseRelationship = relationFrom

        relationFrom.name = "relationFrom"
        relationFrom.isOptional = false
        relationFrom.destinationEntity = entity
        relationFrom.minCount = 0
        relationFrom.maxCount = 1
        relationFrom.deleteRule = .nullifyDeleteRule
        relationFrom.inverseRelationship = relationTo

        properties.append(relationTo)
        properties.append(relationFrom)

        entity.properties = properties
        model.entities = [entity]
        return model
    }

    override func setUp() {
        super.setUp()

        db = CoreDataDatabase(name: "Test",
                              containerLocation: tempDBDir(),
                              model: testModel())
        db.loadStore()
    }

    override func tearDown() async throws {

        try db.tearDown(deleteStores: true)
        try await super.tearDown()
    }

    func testWhenObjectsAreValidThenTheyAreSaved() throws {

        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)

        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e1.attribute = "e1"
        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        try context.save()
    }

    func testWhenOneAttributesAreMissingThenErrorIsIdentified() {

        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)

        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        do {
            try context.save()
            XCTFail("This must fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            XCTAssertEqual(info.first?.entity, TestEntity.name)
            XCTAssertEqual(info.first?.property, "attribute")
        }
    }

    func testWhenMoreAttributesAreMissingThenErrorIsIdentified() {

        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)

        _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        do {
            try context.save()
            XCTFail("This must fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            XCTAssertEqual(info.count, 4)

            let uniqueSet = Set(info.map { $0.property })
            XCTAssertEqual(uniqueSet, ["attribute", "relationFrom"])
        }
    }

    func testWhenStoreIsReadOnlyThenErrorIsIdentified() {

        guard let url = db.coordinator.persistentStores.first?.url else {
            XCTFail("Failed to get persistent store URL")
            return
        }
        let ro = CoreDataDatabase(name: "Test",
                                  containerLocation: url.deletingLastPathComponent(),
                                  model: testModel(),
                                  readOnly: true)
        ro.loadStore { _, error in
            XCTAssertNil(error)
        }
        let context = ro.makeContext(concurrencyType: .mainQueueConcurrencyType)

        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e1.attribute = "e1"
        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        do {
            try context.save()
            XCTFail("This must fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            XCTAssertEqual(info.first?.domain, NSCocoaErrorDomain)
            XCTAssertEqual(info.first?.code, 513)
        }
    }

    func testWhenThereIsMergeConflictThenErrorIsIdentified() throws {

        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)

        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e1.attribute = "e1"
        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        try context.save()

        let anotherContext = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        guard let anotherE1 = try anotherContext.existingObject(with: e1.objectID) as? TestEntity else {
            XCTFail("Expected object")
            return
        }

        e1.attribute = "e1updated"
        try context.save()

        anotherE1.attribute = "e1ConflictingUpdate"

        do {
            try anotherContext.save()
            XCTFail("This must fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            XCTAssertEqual(info.first?.domain, NSCocoaErrorDomain)
            XCTAssertEqual(info.first?.entity, TestEntity.name)
        }
    }
}
