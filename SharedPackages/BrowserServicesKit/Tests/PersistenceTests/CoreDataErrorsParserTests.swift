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

import CoreData
import Foundation
import Persistence
import Testing

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

final class CoreDataErrorsParserTests {

    static func tempDBDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    var db: CoreDataDatabase

    static func testModel() -> NSManagedObjectModel {
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

    init() {
        db = CoreDataDatabase(name: "Test",
                              containerLocation: Self.tempDBDir(),
                              model: Self.testModel())
        db.loadStore()
    }

    deinit {
        try? db.tearDown(deleteStores: true)
    }

    @Test("Valid objects are saved successfully")
    func validObjectsAreSaved() throws {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)

        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e1.attribute = "e1"
        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        try context.save()
    }

    @Test("Missing attribute error is identified")
    func missingAttributeErrorIdentified() throws {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)

        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        do {
            try context.save()
            Issue.record("Expected save to fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            #expect(info.first?.entity == TestEntity.name)
            #expect(info.first?.property == "attribute")
        }
    }

    @Test("Multiple missing attributes are identified")
    func multipleAttributesMissing() throws {
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)

        _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        _ = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        do {
            try context.save()
            Issue.record("Expected save to fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            #expect(info.count == 4)

            let uniqueSet = Set(info.map { $0.property })
            #expect(uniqueSet == ["attribute", "relationFrom"])
        }
    }

    @Test("Read-only store error is identified")
    func readOnlyStoreError() throws {
        guard let url = db.coordinator.persistentStores.first?.url else {
            Issue.record("Failed to get persistent store URL")
            return
        }
        let ro = CoreDataDatabase(name: "Test",
                                  containerLocation: url.deletingLastPathComponent(),
                                  model: Self.testModel(),
                                  readOnly: true)
        ro.loadStore { _, error in
            #expect(error == nil)
        }
        let context = ro.makeContext(concurrencyType: NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType)

        let e1 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)
        let e2 = TestEntity(entity: TestEntity.entity(in: context), insertInto: context)

        e1.attribute = "e1"
        e2.attribute = "e2"
        e1.relationTo = e2
        e2.relationTo = e1

        do {
            try context.save()
            Issue.record("Expected save to fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            #expect(info.first?.domain == NSCocoaErrorDomain)
            #expect(info.first?.code == 513)
        }
    }

    @Test("Merge conflict error is identified")
    func mergeConflictError() throws {
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
            Issue.record("Expected object to exist")
            return
        }

        e1.attribute = "e1updated"
        try context.save()

        anotherE1.attribute = "e1ConflictingUpdate"

        do {
            try anotherContext.save()
            Issue.record("Expected save to fail")
        } catch {
            let error = error as NSError

            let info = CoreDataErrorsParser.parse(error: error)
            #expect(info.first?.domain == NSCocoaErrorDomain)
            #expect(info.first?.entity == TestEntity.name)
        }
    }
}
