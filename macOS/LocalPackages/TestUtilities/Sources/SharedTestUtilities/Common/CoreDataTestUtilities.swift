//
//  CoreDataTestUtilities.swift
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

import CoreData
import Foundation
import Utilities
import os.log

public final class CoreData {

    public static func historyStoreContainer() -> NSPersistentContainer {
        createInMemoryPersistentContainer(modelName: "History", bundle: Bundle.main)
    }

    public static func legacyBookmarkContainer() -> NSPersistentContainer {
        return createInMemoryPersistentContainer(modelName: "Bookmark", bundle: Bundle.main)
    }

    public static func permissionContainer() -> NSPersistentContainer {
        return createInMemoryPersistentContainer(modelName: "Permissions", bundle: Bundle.main)
    }

    public static func fireproofingContainer() -> NSPersistentContainer {
        return createInMemoryPersistentContainer(modelName: "FireproofDomains", bundle: Bundle.main)
    }

    public static func coreDataStoreTestsContainer(bundle: Bundle) -> NSPersistentContainer {
        return createInMemoryPersistentContainer(modelName: "TestDataModel", bundle: bundle)
    }

    public static func downloadsContainer() -> NSPersistentContainer {
        return createInMemoryPersistentContainer(modelName: "Downloads", bundle: Bundle.main)
    }

    public static func createPersistentContainer(at url: URL, modelName: String, bundle: Bundle, keyStore: EncryptionKeyStoring) -> NSPersistentContainer {
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "momd") ?? bundle.url(forResource: modelName, withExtension: "xcdatamodeld") else {
            fatalError("Error loading model \(modelName) from \(bundle)\n\(Thread.callStackSymbols.joined(separator: "\n"))")
        }

        guard let objectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Error initializing object model from: \(modelURL)")
        }

        let transformers = objectModel.registerValueTransformers(keyStore: keyStore)
        let container = TestPersistentContainer(name: modelName,
                                                managedObjectModel: objectModel,
                                                registeredTransformers: transformers)

        let description = NSPersistentStoreDescription()
        description.url = url
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error as NSError? {
                fatalError("Failed to load stores: \(error), \(error.userInfo)")
            }
        })

        return container
    }

    public static func createInMemoryPersistentContainer(modelName: String, bundle: Bundle, keyStore: EncryptionKeyStoring = EncryptionKeyStoreMock()) -> NSPersistentContainer {
        // Creates a persistent store using the in-memory model, no state will be written to disk.
        // This was the approach I had seen recommended in a WWDC session, but there is also a
        // `NSInMemoryStoreType` option for doing this.
        //
        // This approach is apparently the recommended choice: https://www.donnywals.com/setting-up-a-core-data-store-for-unit-tests/
        return createPersistentContainer(at: URL(fileURLWithPath: "/dev/null"), modelName: modelName, bundle: bundle, keyStore: keyStore)
    }

}

public final class TestPersistentContainer: NSPersistentContainer {
    public let registeredTransformers: [NSValueTransformerName]
    public init(name: String, managedObjectModel model: NSManagedObjectModel, registeredTransformers: [NSValueTransformerName]) {
        self.registeredTransformers = registeredTransformers
        super.init(name: name, managedObjectModel: model)
    }

    deinit {
        for name in registeredTransformers {
            ValueTransformer.setValueTransformer(nil, forName: name)
        }
    }
}
