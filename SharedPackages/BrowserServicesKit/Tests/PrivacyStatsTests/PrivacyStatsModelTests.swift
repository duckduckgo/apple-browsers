//
//  PrivacyStatsModelTests.swift
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

@testable import PrivacyStats

/// Entity version hashes of every shipped schema version, as compiled by `momc` from the former
/// `PrivacyStats.xcdatamodeld`. A mismatch means a shipped version was changed and existing stores
/// would no longer match it — add a new version instead.
final class PrivacyStatsModelTests: XCTestCase {

    func testV1MatchesShippedVersionHashes() {
        let model = NSManagedObjectModel(entities: PrivacyStatsModel.v1())

        XCTAssertEqual(model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, [
            "DailyBlockedTrackersEntity": "FzgGwKuV5MxquRXE/MDAX/fkdfsBz/AbiBnsfLqdFUI=",
        ])
    }

    func testCurrentModelIsLatestVersionBoundToManagedObjectSubclass() {
        let current = VersionedManagedObjectModel.privacyStats.current

        XCTAssertEqual(current.entityVersionHashesByName, NSManagedObjectModel(entities: PrivacyStatsModel.v1()).entityVersionHashesByName)
        XCTAssertEqual(current.entitiesByName["DailyBlockedTrackersEntity"]?.managedObjectClassName,
                       NSStringFromClass(DailyBlockedTrackersEntity.self))
    }
}
