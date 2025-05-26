//
//  SyncMetadataMigrationTests.swift
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

import BookmarksTestsUtils
import XCTest
import Persistence
@testable import DDGSync
import Foundation

class SyncMetadataMigrationTests: XCTestCase {

    var location: URL!
    var resourceURLDir: URL!

    override func setUp() {
        super.setUp()

        ModelAccessHelper.compileModel(from: Bundle(for: SyncMetadataMigrationTests.self), named: "SyncMetadata")

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        guard let location = Bundle(for: SyncMetadataMigrationTests.self).resourceURL else {
            XCTFail("Failed to find bundle URL")
            return
        }

        let resourcesLocation = location.appendingPathComponent( "BrowserServicesKit_DDGTests.bundle/Contents/Resources/")
        if FileManager.default.fileExists(atPath: resourcesLocation.path) == false {
            resourceURLDir = Bundle.module.resourceURL
        } else {
            resourceURLDir = resourcesLocation
        }
    }

    override func tearDown() {
        super.tearDown()

        try? FileManager.default.removeItem(at: location)
    }

    func copyDatabase(name: String, formDirectory: URL, toDirectory: URL) throws {

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: toDirectory, withIntermediateDirectories: false)
        for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {

            try fileManager.copyItem(at: formDirectory.appendingPathComponent("\(name).\(ext)"),
                                     to: toDirectory.appendingPathComponent("\(name).\(ext)"))
        }
    }

    func loadDatabase(name: String) -> CoreDataDatabase? {
        let bundle = DDGSync.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "SyncMetadata") else {
            return nil
        }
        let syncMetadataDatabase = CoreDataDatabase(name: name, containerLocation: location, model: model)
        syncMetadataDatabase.loadStore()
        return syncMetadataDatabase
    }

    func testWhenMigratingFromV3ThenDataIsPreserved() throws {
        try commonMigrationTestForDatabase(name: "SyncMetadata_V3")
    }

    func commonMigrationTestForDatabase(name: String) throws {

        try copyDatabase(name: name, formDirectory: resourceURLDir, toDirectory: location)

        guard let migratedStack = loadDatabase(name: name) else {
            XCTFail("Could not initialize legacy stack")
            return
        }

        let latestContext = migratedStack.makeContext(concurrencyType: .privateQueueConcurrencyType)
        try latestContext.performAndWait({

            let featureName1 = "TestFeature-01"
            let featureName2 = "TestFeature-02"
            let metadataStore = LocalSyncMetadataStore(context: latestContext)
            XCTAssertTrue(metadataStore.isFeatureRegistered(named: featureName1))
            XCTAssertTrue(metadataStore.isFeatureRegistered(named: featureName2))
            XCTAssertEqual(metadataStore.state(forFeatureNamed: featureName1), .needsRemoteDataFetch)
            XCTAssertEqual(metadataStore.state(forFeatureNamed: featureName2), .readyToSync)
            XCTAssertNil(metadataStore.timestamp(forFeatureNamed: featureName1))
            XCTAssertEqual(metadataStore.timestamp(forFeatureNamed: featureName2), "1234")

            let settingName1 = "TestSetting-01"
            let settingName2 = "TestSetting-02"
            let setting1 = try XCTUnwrap(SyncableSettingsMetadataUtils.fetchSettingsMetadata(with: settingName1, in: latestContext))
            let setting2 = try XCTUnwrap(SyncableSettingsMetadataUtils.fetchSettingsMetadata(with: settingName2, in: latestContext))
            XCTAssertNil(setting1.lastModified)
            XCTAssertNotNil(setting2.lastModified)
        })

        try? migratedStack.tearDown(deleteStores: true)
    }

    func testThatMigrationToV4SetsLocalSyncTimestampsForFeaturesToNil() async throws {

        try copyDatabase(name: "SyncMetadata_V3", formDirectory: resourceURLDir, toDirectory: location)

        guard let syncMetadataDatabase = loadDatabase(name: "SyncMetadata_V3") else {
            XCTFail("Failed to load model")
            return
        }

        let context = syncMetadataDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            let featureName1 = "TestFeature-01"
            let featureName2 = "TestFeature-02"
            let metadataStore = LocalSyncMetadataStore(context: context)
            XCTAssertTrue(metadataStore.isFeatureRegistered(named: featureName1))
            XCTAssertTrue(metadataStore.isFeatureRegistered(named: featureName2))

            XCTAssertNil(metadataStore.localTimestamp(forFeatureNamed: featureName1))
            XCTAssertNil(metadataStore.localTimestamp(forFeatureNamed: featureName2))
        }

        try? syncMetadataDatabase.tearDown(deleteStores: true)
    }
}
