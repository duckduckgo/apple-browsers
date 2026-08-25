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

import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import XCTest
@_spi(Testing) import Persistence

@testable import DuckDuckGo_Privacy_Browser

final class DataDirectoryPermissionFixAvailabilityTests: XCTestCase {

    private var debugSettings: (any KeyedStoring<DataImportDebugSettings>)!

    /// `isAvailable` gates on `#available(macOS 27.0, *)`, which can't be injected: the OS floor
    /// can only be asserted relative to the OS the suite happens to run on.
    private var isRunningMacOS27OrLater: Bool {
        if #available(macOS 27.0, *) {
            return true
        }
        return false
    }

    override func setUp() {
        super.setUp()
        debugSettings = InMemoryKeyValueStore().keyedStoring()
    }

    override func tearDown() {
        debugSettings = nil
        super.tearDown()
    }

    // MARK: - isAvailable

    func testWhenTheFeatureFlagIsOn_ThenItIsAvailableOnlyOnMacOS27OrLater() {
        let availability = makeAvailability(isFeatureFlagOn: true)

        XCTAssertEqual(availability.isAvailable, isRunningMacOS27OrLater)
    }

    func testWhenTheFeatureFlagIsOff_ThenItIsNotAvailable() {
        let availability = makeAvailability(isFeatureFlagOn: false)

        XCTAssertFalse(availability.isAvailable)
    }

    // MARK: - Debug override

    func testWhenTheDebugOverrideIsOn_ThenItIsAvailableRegardlessOfTheOSVersionAndTheFeatureFlag() {
        debugSettings.isForcingMacOS27PermissionsFix = true
        let availability = makeAvailability(isFeatureFlagOn: false)

        XCTAssertTrue(availability.isAvailable)
    }

    func testWhenTheDebugOverrideIsOn_ThenPermissionFixIsForced() {
        debugSettings.isForcingMacOS27PermissionsFix = true
        let availability = makeAvailability(isFeatureFlagOn: false)

        XCTAssertTrue(availability.mustForcePermissionFix)
    }

    func testWhenTheDebugOverrideIsOff_ThenPermissionFixIsNotForced() {
        debugSettings.isForcingMacOS27PermissionsFix = false
        let availability = makeAvailability(isFeatureFlagOn: true)

        // Available on macOS 27+, but never *forced*: the flow still keys off the directory's actual access state.
        XCTAssertFalse(availability.mustForcePermissionFix)
    }

    func testWhenTheDebugOverrideWasNeverSet_ThenPermissionFixIsNotForced() {
        let availability = makeAvailability(isFeatureFlagOn: false)

        XCTAssertFalse(availability.mustForcePermissionFix)
    }

    // MARK: - Helpers

    private func makeAvailability(isFeatureFlagOn: Bool) -> DataDirectoryPermissionFixAvailability {
        let featureFlagger = MockFeatureFlagger(
            featuresStub: [FeatureFlag.dataImportDataDirectoryAccess.rawValue: isFeatureFlagOn]
        )

        return DataDirectoryPermissionFixAvailability(
            featureFlagger: featureFlagger,
            debugSettings: debugSettings
        )
    }
}
