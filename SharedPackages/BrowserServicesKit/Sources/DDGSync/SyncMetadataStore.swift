//
//  SyncMetadataStore.swift
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
import Persistence
import CoreData

public protocol SyncMetadataStore {
    func isFeatureRegistered(named name: String) -> Bool
    func registerFeature(named name: String, setupState: FeatureSetupState) throws
    func deregisterFeature(named name: String) throws

    func timestamp(forFeatureNamed name: String) -> String?
    func localTimestamp(forFeatureNamed name: String) -> Date?
    func updateLocalTimestamp(_ localTimestamp: Date?, forFeatureNamed name: String)

    func state(forFeatureNamed name: String) -> FeatureSetupState

    func update(_ serverTimestamp: String?, _ localTimestamp: Date?, _ state: FeatureSetupState, forFeatureNamed name: String)
}

public final class LocalSyncMetadataStore: SyncMetadataStore {

    public init(database: CoreDataDatabase) {
        self.context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
    }

    public init(context: NSManagedObjectContext) {
        self.context = context
    }

    public func isFeatureRegistered(named name: String) -> Bool {
        context.performAndWait { [context] in
            SyncFeatureUtils.fetchFeature(with: name, in: context) != nil
        }
    }

    public func registerFeature(named name: String, setupState: FeatureSetupState) throws {
        try context.performAndWait { [context] in
            if SyncFeatureUtils.fetchFeature(with: name, in: context) != nil {
                return
            }

            SyncFeatureEntity.makeFeature(with: name, state: setupState, in: context)
            try context.save()
        }
    }

    public func deregisterFeature(named name: String) throws {
        try context.performAndWait { [context] in
            guard let feature = SyncFeatureUtils.fetchFeature(with: name, in: context) else {
                return
            }

            context.delete(feature)
            try context.save()
        }
    }

    public func timestamp(forFeatureNamed name: String) -> String? {
        context.performAndWait { [context] in
            SyncFeatureUtils.fetchFeature(with: name, in: context)?.lastModified
        }
    }

    public func localTimestamp(forFeatureNamed name: String) -> Date? {
        context.performAndWait { [context] in
            SyncFeatureUtils.fetchFeature(with: name, in: context)?.lastSyncLocalTimestamp
        }
    }

    public func state(forFeatureNamed name: String) -> FeatureSetupState {
        context.performAndWait { [context] in
            SyncFeatureUtils.fetchFeature(with: name, in: context)?.featureState ?? .readyToSync
        }
    }

    public func updateLocalTimestamp(_ localTimestamp: Date?, forFeatureNamed name: String) {
        context.performAndWait { [context] in
            let feature = SyncFeatureUtils.fetchFeature(with: name, in: context)
            feature?.lastSyncLocalTimestamp = localTimestamp
            try? context.save()
        }
    }

    public func update(_ serverTimestamp: String?, _ localTimestamp: Date?, _ state: FeatureSetupState, forFeatureNamed name: String) {
        context.performAndWait { [context] in
            let feature = SyncFeatureUtils.fetchFeature(with: name, in: context)
            feature?.lastModified = serverTimestamp
            feature?.lastSyncLocalTimestamp = localTimestamp
            feature?.featureState = state

            try? context.save()
        }
    }

    let context: NSManagedObjectContext
}
