//
//  SyncMetadataTestDBBuilder.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DDGSync

// swiftlint:disable force_try

@main
struct SyncMetadataTestDBBuilder {

    static func main() {
        generateDatabase(modelVersion: 3)
    }

    private static func generateDatabase(modelVersion: Int) {
        let bundle = DDGSync.bundle
        var momUrl: URL?
        if modelVersion == 1 {
            momUrl = bundle.url(forResource: "SyncMetadata.momd/SyncMetadata", withExtension: "mom")
        } else {
            momUrl = bundle.url(forResource: "SyncMetadata.momd/SyncMetadata \(modelVersion)", withExtension: "mom")
        }

        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            fatalError("Could not find directory")
        }

        let model = NSManagedObjectModel(contentsOf: momUrl!)
        let stack = CoreDataDatabase(name: "SyncMetadata_V\(modelVersion)",
                                     containerLocation: dir,
                                     model: model!)
        stack.loadStore()

        let context = stack.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            populateTestData(in: context)
        }
    }

    private static func populateTestData(in context: NSManagedObjectContext) {
        /* When modifying, please add requirements to list below
         - Test Sync features, in 2 possible states, with and without a timestamp
         - Test Syncable Settings Metadata, with and without a timestamp
         */
        let featureName1 = "TestFeature-01"
        let featureName2 = "TestFeature-02"
        SyncFeatureEntity.makeFeature(with: featureName1, state: .needsRemoteDataFetch, in: context)
        SyncFeatureEntity.makeFeature(with: featureName2, lastModified: "1234", state: .readyToSync, in: context)

        let settingName1 = "TestSetting-01"
        let settingName2 = "TestSetting-02"
        SyncableSettingsMetadata.makeSettingsMetadata(with: settingName1, in: context)
        SyncableSettingsMetadata.makeSettingsMetadata(with: settingName2, lastModified: Date(), in: context)

        try! context.save()
    }
}

// swiftlint:enable force_try
