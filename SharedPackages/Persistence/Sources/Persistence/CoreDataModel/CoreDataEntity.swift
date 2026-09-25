//
//  CoreDataEntity.swift
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
import Foundation

/// A code-defined Core Data entity: a value-type description that builds a fresh `NSEntityDescription`
/// every time a model is made from it.
///
/// Defaults mirror what `momc` produces for an `.xcdatamodel` entry with the same fields,
/// so a definition transcribed 1:1 from the model editor yields the same entity version hash
/// and opens stores created with the compiled `.momd`.
public struct CoreDataEntity {

    public var name: String
    /// Objective-C runtime name of the `NSManagedObject` subclass; `nil` means plain `NSManagedObject`.
    public var className: String?
    public var attributes: [CoreDataAttribute]
    public var relationships: [CoreDataRelationship]
    public var indexes: [CoreDataIndex]
    public var uniquenessConstraints: [[String]]
    public var renamingIdentifier: String?
    public var versionHashModifier: String?

    public init(_ name: String,
                className: String?,
                attributes: [CoreDataAttribute] = [],
                relationships: [CoreDataRelationship] = [],
                indexes: [CoreDataIndex] = [],
                uniquenessConstraints: [[String]] = [],
                renamingIdentifier: String? = nil,
                versionHashModifier: String? = nil) {
        self.name = name
        self.className = className
        self.attributes = attributes
        self.relationships = relationships
        self.indexes = indexes
        self.uniquenessConstraints = uniquenessConstraints
        self.renamingIdentifier = renamingIdentifier
        self.versionHashModifier = versionHashModifier
    }
}

public struct CoreDataAttribute {

    public var name: String
    public var type: NSAttributeType
    public var isOptional: Bool
    public var defaultValue: Any?
    public var valueTransformerName: String?
    public var valueClassName: String?
    public var renamingIdentifier: String?
    public var allowsExternalBinaryDataStorage: Bool

    public init(_ name: String,
                _ type: NSAttributeType,
                optional: Bool = false,
                defaultValue: Any? = nil,
                valueTransformerName: String? = nil,
                valueClassName: String? = nil,
                renamingIdentifier: String? = nil,
                allowsExternalBinaryDataStorage: Bool = false) {
        self.name = name
        self.type = type
        self.isOptional = optional
        self.defaultValue = defaultValue
        self.valueTransformerName = valueTransformerName
        self.valueClassName = valueClassName
        self.renamingIdentifier = renamingIdentifier
        self.allowsExternalBinaryDataStorage = allowsExternalBinaryDataStorage
    }

    func makeDescription() -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        attribute.valueTransformerName = valueTransformerName
        attribute.renamingIdentifier = renamingIdentifier
        attribute.allowsExternalBinaryDataStorage = allowsExternalBinaryDataStorage
        if let valueClassName {
            attribute.attributeValueClassName = valueClassName
        }
        return attribute
    }
}

public struct CoreDataRelationship {

    public var name: String
    public var destination: String
    /// Name of the inverse relationship on `destination`.
    public var inverse: String?
    public var isOptional: Bool
    public var isToMany: Bool
    public var isOrdered: Bool
    public var deleteRule: NSDeleteRule
    public var renamingIdentifier: String?

    public static func toOne(_ name: String,
                             _ destination: String,
                             inverse: String?,
                             optional: Bool = false,
                             deleteRule: NSDeleteRule = .nullifyDeleteRule,
                             renamingIdentifier: String? = nil) -> CoreDataRelationship {
        CoreDataRelationship(name: name, destination: destination, inverse: inverse, isOptional: optional,
                             isToMany: false, isOrdered: false, deleteRule: deleteRule, renamingIdentifier: renamingIdentifier)
    }

    public static func toMany(_ name: String,
                              _ destination: String,
                              inverse: String?,
                              optional: Bool = false,
                              ordered: Bool = false,
                              deleteRule: NSDeleteRule = .nullifyDeleteRule,
                              renamingIdentifier: String? = nil) -> CoreDataRelationship {
        CoreDataRelationship(name: name, destination: destination, inverse: inverse, isOptional: optional,
                             isToMany: true, isOrdered: ordered, deleteRule: deleteRule, renamingIdentifier: renamingIdentifier)
    }

    func makeDescription() -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.isOptional = isOptional
        relationship.isOrdered = isOrdered
        relationship.deleteRule = deleteRule
        relationship.renamingIdentifier = renamingIdentifier
        // momc leaves minCount at 0 for non-optional relationships too; maxCount 0 means unbounded.
        relationship.minCount = 0
        relationship.maxCount = isToMany ? 0 : 1
        return relationship
    }
}

/// A fetch index of binary-collated, ascending elements.
public struct CoreDataIndex {

    public var name: String
    public var properties: [String]

    public init(_ name: String, properties: [String]) {
        self.name = name
        self.properties = properties
    }
}

public extension Array where Element == CoreDataEntity {

    /// Lets a model version be written as a change to the previous one.
    mutating func modify(_ entityName: String, _ change: (inout CoreDataEntity) -> Void) {
        guard let index = firstIndex(where: { $0.name == entityName }) else {
            preconditionFailure("No entity named \(entityName)")
        }
        change(&self[index])
    }
}

public extension NSManagedObjectModel {

    /// Builds a model from code-defined entities, resolving relationship destinations and inverses by name.
    ///
    /// - Parameter bindsClasses: pass `false` to map every entity to plain `NSManagedObject`. Historical model
    ///   versions used for migration must not claim the app's `NSManagedObject` subclasses, which only fit
    ///   the current version.
    convenience init(entities definitions: [CoreDataEntity], bindsClasses: Bool = true) {
        self.init()

        var entitiesByName = [String: NSEntityDescription]()
        var relationshipsByEntity = [String: [String: NSRelationshipDescription]]()
        for definition in definitions {
            let entity = NSEntityDescription()
            entity.name = definition.name
            entity.managedObjectClassName = bindsClasses ? definition.className : nil
            entity.renamingIdentifier = definition.renamingIdentifier
            entity.versionHashModifier = definition.versionHashModifier

            let relationships = definition.relationships.map { ($0.name, $0.makeDescription()) }
            relationshipsByEntity[definition.name] = Dictionary(uniqueKeysWithValues: relationships)
            entity.properties = definition.attributes.map { $0.makeDescription() } + relationships.map(\.1)
            entitiesByName[definition.name] = entity
        }

        for definition in definitions {
            for relationship in definition.relationships {
                guard let description = relationshipsByEntity[definition.name]?[relationship.name],
                      let destination = entitiesByName[relationship.destination] else {
                    preconditionFailure("\(definition.name).\(relationship.name): no entity named \(relationship.destination)")
                }
                description.destinationEntity = destination
                guard let inverse = relationship.inverse else { continue }
                guard let inverseDescription = relationshipsByEntity[relationship.destination]?[inverse] else {
                    preconditionFailure("\(definition.name).\(relationship.name): no inverse \(relationship.destination).\(inverse)")
                }
                description.inverseRelationship = inverseDescription
            }
        }

        // Indexes and constraints reference property descriptions, so they are set once properties are in place.
        for definition in definitions {
            guard let entity = entitiesByName[definition.name] else { continue }
            entity.uniquenessConstraints = definition.uniquenessConstraints
            entity.indexes = definition.indexes.map { index in
                let elements = index.properties.map { name in
                    guard let property = entity.propertiesByName[name] else {
                        preconditionFailure("\(definition.name) index \(index.name): no property named \(name)")
                    }
                    return NSFetchIndexElementDescription(property: property, collationType: .binary)
                }
                return NSFetchIndexDescription(name: index.name, elements: elements)
            }
        }

        entities = definitions.compactMap { entitiesByName[$0.name] }
    }
}
