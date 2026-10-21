//
//  DataDirectoryPermissionFixAvailabilityTests.swift
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

import Foundation
import XCTest
@_spi(Testing) import Persistence

@testable import DuckDuckGo_Privacy_Browser

final class DataDirectoryPermissionFixAvailabilityTests: XCTestCase {

    private var debugSettings: (any KeyedStoring<DataImportDebugSettings>)!

    override func setUp() {
        super.setUp()
        debugSettings = InMemoryKeyValueStore().keyedStoring()
    }

    override func tearDown() {
        debugSettings = nil
        super.tearDown()
    }

    // MARK: - isAvailable

    func testWhenTheOSIsSupported_ThenItIsAvailable() {
        let availability = makeAvailability(isOSSupported: true)

        XCTAssertTrue(availability.isAvailable)
    }

    func testWhenTheOSIsNotSupported_ThenItIsNotAvailable() {
        let availability = makeAvailability(isOSSupported: false)

        XCTAssertFalse(availability.isAvailable)
    }

    // MARK: - Debug override

    func testWhenTheDebugOverrideIsOn_ThenItIsAvailableRegardlessOfTheOSVersion() {
        debugSettings.isForcingMacOS27PermissionsFix = true
        let availability = makeAvailability(isOSSupported: false)

        XCTAssertTrue(availability.isAvailable)
    }

    func testWhenTheDebugOverrideIsOn_ThenPermissionFixIsForced() {
        debugSettings.isForcingMacOS27PermissionsFix = true
        let availability = makeAvailability()

        XCTAssertTrue(availability.mustForcePermissionFix)
    }

    func testWhenTheDebugOverrideIsOff_ThenPermissionFixIsNotForced() {
        debugSettings.isForcingMacOS27PermissionsFix = false
        let availability = makeAvailability()

        // Available, but never *forced*: the flow still keys off the directory's actual access state.
        XCTAssertFalse(availability.mustForcePermissionFix)
    }

    func testWhenTheDebugOverrideWasNeverSet_ThenPermissionFixIsNotForced() {
        let availability = makeAvailability()

        XCTAssertFalse(availability.mustForcePermissionFix)
    }

    // MARK: - Helpers

    private func makeAvailability(isOSSupported: Bool = true) -> DataDirectoryPermissionFixAvailability {
        DataDirectoryPermissionFixAvailability(
            debugSettings: debugSettings,
            isOSSupported: isOSSupported
        )
    }
}
