//
//  HTTPSUpgradeModelTests.swift
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
@testable import BrowserServicesKit

/// Entity version hashes of the shipped schema version, as compiled by `momc` from the former
/// `HTTPSUpgrade.xcdatamodeld`. A mismatch means a shipped version was changed and existing stores
/// would no longer match it — add a new version instead.
final class HTTPSUpgradeModelTests: XCTestCase {

    func testV3MatchesShippedVersionHashes() {
        let model = NSManagedObjectModel(entities: HTTPSUpgradeModel.v3())

        XCTAssertEqual(model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, [
            "HTTPSExcludedDomain": "AXncKdruj21wCoJtV3yEgalwrdjSrEWEe0fBsMGPICY=",
            "HTTPSStoredBloomFilterSpecification": "cWqVixoTyMQdUE7ByoUDR1YMH2gvR917pElFmxC+RZU=",
        ])
    }

    func testManagedObjectModelIsLatestVersionBoundToManagedObjectSubclasses() {
        let model = HTTPSUpgrade.managedObjectModel

        XCTAssertEqual(model.entityVersionHashesByName, NSManagedObjectModel(entities: HTTPSUpgradeModel.v3()).entityVersionHashesByName)
        XCTAssertEqual(model.entitiesByName.mapValues(\.managedObjectClassName), [
            "HTTPSExcludedDomain": NSStringFromClass(HTTPSExcludedDomain.self),
            "HTTPSStoredBloomFilterSpecification": NSStringFromClass(HTTPSStoredBloomFilterSpecification.self),
        ])
    }
}
