//
//  CoreDataDatabase.swift
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
import Common

public protocol CoreDataStoring {

    var isDatabaseFileInitialized: Bool { get }
    var model: NSManagedObjectModel { get }
    var coordinator: NSPersistentStoreCoordinator { get }

    func loadStore(completion: @escaping (NSManagedObjectContext?, Swift.Error?) -> Void)

    func makeContext(concurrencyType: NSManagedObjectContextConcurrencyType, name: String?) -> NSManagedObjectContext
}

public extension CoreDataStoring {

    func makeContext(concurrencyType: NSManagedObjectContextConcurrencyType) -> NSManagedObjectContext {
        makeContext(concurrencyType: concurrencyType, name: nil)
    }
}

public class CoreDataDatabase: CoreDataStoring {

    public enum Error: Swift.Error {
        case containerLocationCouldNotBePrepared(underlyingError: Swift.Error)
    }

    private let containerLocation: URL
    private let container: NSPersistentContainer
    private let storeLoadedCondition = RunLoop.ResumeCondition()

    public var isDatabaseFileInitialized: Bool {
        guard let containerURL = container.persistentStoreDescriptions.first?.url else { return false }

        return FileManager.default.fileExists(atPath: containerURL.path)
    }

    public var model: NSManagedObjectModel {
        return container.managedObjectModel
    }

    public var coordinator: NSPersistentStoreCoordinator {
        return container.persistentStoreCoordinator
    }

    public static func loadModel(from bundle: Bundle, named name: String) -> NSManagedObjectModel? {
        let momdUrl = bundle.url(forResource: name, withExtension: "momd") ??
            bundle.resourceURL!.appendingPathComponent(name + ".momd")
#if DEBUG && os(macOS)
        // when running tests using `swift test` xcdatamodeld is not compiled to momd for some reason
        // this is a workaround to compile it in runtime
        if !FileManager.default.fileExists(atPath: momdUrl.path),
           let xcDataModelUrl = bundle.url(forResource: name, withExtension: "xcdatamodeld"),
           let sdkRoot = ProcessInfo().environment["SDKROOT"],
           let developerDir = sdkRoot.range(of: "/Contents/Developer").map({ sdkRoot[..<$0.upperBound] }) {

            let compileDataModel = Process()
            let momc = "\(developerDir)/usr/bin/momc"
            compileDataModel.executableURL = URL(fileURLWithPath: momc)
            compileDataModel.arguments = [xcDataModelUrl.path, momdUrl.path]
            try? compileDataModel.run()
            compileDataModel.waitUntilExit()
        }
#endif
        guard FileManager.default.fileExists(atPath: momdUrl.path) else { return nil }

        return NSManagedObjectModel(contentsOf: momdUrl)
    }

    public init(name: String,
                containerLocation: URL,
                model: NSManagedObjectModel,
                readOnly: Bool = false,
                options: [String: NSObject] = [:]) {

        self.container = NSPersistentContainer(name: name, managedObjectModel: model)
        self.containerLocation = containerLocation

        let description = NSPersistentStoreDescription(url: containerLocation.appendingPathComponent("\(name).sqlite"))
        description.type = NSSQLiteStoreType
        description.isReadOnly = readOnly

        for (key, value) in options {
            description.setOption(value, forKey: key)
        }

        self.container.persistentStoreDescriptions = [description]
    }

    public func loadStore(completion: @escaping (NSManagedObjectContext?, Swift.Error?) -> Void = { _, _ in }) {

        do {
            try FileManager.default.createDirectory(at: containerLocation, withIntermediateDirectories: true)
        } catch {
            completion(nil, Error.containerLocationCouldNotBePrepared(underlyingError: error))
            return
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                completion(nil, error)
                return
            }

            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = self.container.persistentStoreCoordinator
            context.name = "Migration"
            context.performAndWait {
                completion(context, nil)
                self.storeLoadedCondition.resolve()
            }
        }
    }

    public func tearDown(deleteStores: Bool) throws {
        typealias StoreInfo = (url: URL?, type: String)
        var storesToDelete = [StoreInfo]()
        for store in container.persistentStoreCoordinator.persistentStores {
            storesToDelete.append((url: store.url, type: store.type))
            try container.persistentStoreCoordinator.remove(store)
        }

        if deleteStores {
            for (url, type) in storesToDelete {
                if let url = url {
                    try container.persistentStoreCoordinator.destroyPersistentStore(at: url, ofType: type)
                }
            }
        }
    }

    public func makeContext(concurrencyType: NSManagedObjectContextConcurrencyType, name: String?) -> NSManagedObjectContext {
        RunLoop.current.run(until: storeLoadedCondition)

        let context = NSManagedObjectContext(concurrencyType: concurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        context.name = name

        return context
    }
}

extension NSManagedObjectContext {

    public func deleteAll(entities: [NSManagedObject] = []) {
        for entity in entities {
            delete(entity)
        }
    }

    public func deleteAll<T: NSManagedObject>(matching request: NSFetchRequest<T>) {
        if let result = try? fetch(request) {
            deleteAll(entities: result)
        }
    }

    public func deleteAll(entityDescriptions: [NSEntityDescription] = []) {
        for entityDescription in entityDescriptions {
            let request = NSFetchRequest<NSManagedObject>()
            request.entity = entityDescription

            deleteAll(matching: request)
        }
    }

}
