//
//  BrowsingHistoryModelTests.swift
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

@testable import History

/// Entity version hashes of every shipped schema version, as compiled by `momc` from the former
/// `BrowsingHistory.xcdatamodeld`. A mismatch means a shipped version was changed and existing stores
/// would no longer match it — add a new version instead.
final class BrowsingHistoryModelTests: XCTestCase {

    func testV1MatchesShippedVersionHashes() {
        XCTAssertEqual(versionHashes(BrowsingHistoryModel.v1()), [
            "BrowsingHistoryEntryManagedObject": "TkH85HGuxH23yzIkZmR14HcAdCVGKo8SVV93Yv3QQZ0=",
            "PageVisitManagedObject": "3k+i+fX0bmFm/Shy5PKiMLd6ShyUpYNKwFoz/GcthLk=",
        ])
    }

    func testV2MatchesShippedVersionHashes() {
        XCTAssertEqual(versionHashes(BrowsingHistoryModel.v2()), [
            "BrowsingHistoryEntryManagedObject": "OFahYXvCkI0L7lC8YgR+Qz8fmxOIDphYCk+3Nr5HDHo=",
            "PageVisitManagedObject": "3k+i+fX0bmFm/Shy5PKiMLd6ShyUpYNKwFoz/GcthLk=",
        ])
    }

    func testV3MatchesShippedVersionHashes() {
        XCTAssertEqual(versionHashes(BrowsingHistoryModel.v3()), [
            "BrowsingHistoryEntryManagedObject": "OFahYXvCkI0L7lC8YgR+Qz8fmxOIDphYCk+3Nr5HDHo=",
            "PageVisitManagedObject": "Y4YPhhUEpHmSg0iZcaixUo1AtqLFp1bwhocYASaE4Os=",
            "TabHistoryManagedObject": "Gehc7KV3DxjKvuUOY92kHAeF0f2hn5IXqrE27SuxF64=",
        ])
    }

    func testCurrentModelIsLatestVersionBoundToManagedObjectSubclasses() {
        let current = VersionedManagedObjectModel.browsingHistory.current

        XCTAssertEqual(current.entityVersionHashesByName, NSManagedObjectModel(entities: BrowsingHistoryModel.v3()).entityVersionHashesByName)
        XCTAssertEqual(current.entitiesByName.mapValues(\.managedObjectClassName), [
            "BrowsingHistoryEntryManagedObject": NSStringFromClass(BrowsingHistoryEntryManagedObject.self),
            "PageVisitManagedObject": NSStringFromClass(PageVisitManagedObject.self),
            "TabHistoryManagedObject": NSStringFromClass(TabHistoryManagedObject.self),
        ])
    }

    private func versionHashes(_ entities: [CoreDataEntity]) -> [String: String] {
        NSManagedObjectModel(entities: entities).entityVersionHashesByName.mapValues { $0.base64EncodedString() }
    }
}
