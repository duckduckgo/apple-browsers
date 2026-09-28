//
//  SyncMetadataModelTests.swift
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
import Persistence
import XCTest
@testable import DDGSync

/// Entity version hashes of every shipped schema version, as compiled by `momc` from the former
/// `SyncMetadata.xcdatamodeld`. A mismatch means a shipped version was changed and existing stores
/// would no longer match it — add a new version instead.
final class SyncMetadataModelTests: XCTestCase {

    func testEveryVersionMatchesShippedVersionHashes() {
        let settingsMetadata = "07TVVttplTirki70JOWjXKp+1ibymh2PA79QnD1zfC0="
        let expected: [[String: String]] = [
            ["SyncFeatureEntity": "xxMGcXZ4grH7CuR4vysic0ELq+BIosS+Fg+W3mgc8co="],
            ["SyncFeatureEntity": "KJuJcDoyFq/pc6B+GIlTTYZQd35E74mZMFacZyHqw1c="],
            ["SyncFeatureEntity": "KJuJcDoyFq/pc6B+GIlTTYZQd35E74mZMFacZyHqw1c=", "SyncableSettingsMetadata": settingsMetadata],
            ["SyncFeatureEntity": "le3O2ZyCHv001PHVXNsL95TdUWmhOOZApBOjG1IMMZ8=", "SyncableSettingsMetadata": settingsMetadata],
        ]
        let versions = [SyncMetadataModel.v1, SyncMetadataModel.v2, SyncMetadataModel.v3, SyncMetadataModel.v4]

        for (index, (version, hashes)) in zip(versions, expected).enumerated() {
            let model = NSManagedObjectModel(entities: version())
            XCTAssertEqual(model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, hashes, "SyncMetadata v\(index + 1)")
        }
    }

    func testCurrentModelIsLatestVersionBoundToManagedObjectSubclasses() {
        let current = VersionedManagedObjectModel.syncMetadata.current

        XCTAssertEqual(current.entityVersionHashesByName, NSManagedObjectModel(entities: SyncMetadataModel.v4()).entityVersionHashesByName)
        XCTAssertEqual(current.entitiesByName.mapValues(\.managedObjectClassName), [
            "SyncFeatureEntity": NSStringFromClass(SyncFeatureEntity.self),
            "SyncableSettingsMetadata": NSStringFromClass(SyncableSettingsMetadata.self),
        ])
    }
}
