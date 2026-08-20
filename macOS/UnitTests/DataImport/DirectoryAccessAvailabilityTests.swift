//
//  DirectoryAccessAvailabilityTests.swift
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
import Persistence
import PersistenceTestingUtils
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DirectoryAccessAvailabilityTests: XCTestCase {

    private var debugSettings: (any KeyedStoring<DataImportDebugSettings>)!

    override func setUp() {
        super.setUp()
        debugSettings = InMemoryKeyValueStore().keyedStoring()
    }

    override func tearDown() {
        debugSettings = nil
        super.tearDown()
    }

    // MARK: - isEnabled

    func testWhenRunningBelowMacOS27_ThenItIsDisabledEvenWithTheFeatureFlagOn() {
        let availability = makeAvailability(isFeatureFlagOn: true, majorVersion: 26)

        XCTAssertFalse(availability.isEnabled)
    }

    func testWhenRunningMacOS27_AndTheFeatureFlagIsOn_ThenItIsEnabled() {
        let availability = makeAvailability(isFeatureFlagOn: true, majorVersion: 27)

        XCTAssertTrue(availability.isEnabled)
    }

    func testWhenRunningMacOS27_AndTheFeatureFlagIsOff_ThenItIsDisabled() {
        let availability = makeAvailability(isFeatureFlagOn: false, majorVersion: 27)

        XCTAssertFalse(availability.isEnabled)
    }

    func testWhenRunningAboveMacOS27_AndTheFeatureFlagIsOn_ThenItIsEnabled() {
        let availability = makeAvailability(isFeatureFlagOn: true, majorVersion: 28)

        XCTAssertTrue(availability.isEnabled)
    }

    // MARK: - Debug override

    func testWhenTheDebugOverrideIsOn_ThenItIsEnabledRegardlessOfTheOSVersionAndTheFeatureFlag() {
        debugSettings.isForcingMacOS27PermissionsFix = true
        let availability = makeAvailability(isFeatureFlagOn: false, majorVersion: 15)

        XCTAssertTrue(availability.isEnabled)
    }

    func testWhenTheDebugOverrideIsOn_ThenPermissionFixIsForced() {
        debugSettings.isForcingMacOS27PermissionsFix = true
        let availability = makeAvailability(isFeatureFlagOn: false, majorVersion: 27)

        XCTAssertTrue(availability.mustForcePermissionFix)
    }

    func testWhenTheDebugOverrideIsOff_ThenPermissionFixIsNotForced() {
        debugSettings.isForcingMacOS27PermissionsFix = false
        let availability = makeAvailability(isFeatureFlagOn: true, majorVersion: 27)

        // Enabled, but not *forced*: the flow still keys off the directory's actual access state.
        XCTAssertFalse(availability.mustForcePermissionFix)
        XCTAssertTrue(availability.isEnabled)
    }

    func testWhenTheDebugOverrideWasNeverSet_ThenPermissionFixIsNotForced() {
        let availability = makeAvailability(isFeatureFlagOn: false, majorVersion: 27)

        XCTAssertFalse(availability.mustForcePermissionFix)
    }

    // MARK: - Helpers

    private func makeAvailability(isFeatureFlagOn: Bool, majorVersion: Int) -> DirectoryAccessAvailability {
        let featureFlagger = MockFeatureFlagger(
            featuresStub: [FeatureFlag.dataImportDataDirectoryAccess.rawValue: isFeatureFlagOn]
        )

        return DirectoryAccessAvailability(
            featureFlagger: featureFlagger,
            debugSettings: debugSettings,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0)
        )
    }
}
