//
//  SupportedOSCheckerTests.swift
//  DuckDuckGo
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

import XCTest
@_spi(Testing) import Persistence
@testable import DuckDuckGo

final class SupportedOSCheckerTests: XCTestCase {

    // MARK: - osUpgradeCapability

    func testWhenModelMaxesOutAtCurrentVersionThenIsIncapable() {
        let checker = SupportedOSChecker(currentOSMajorVersion: 15, hardwareModel: "iPhone9,1")
        XCTAssertEqual(checker.osUpgradeCapability, .incapable)
        XCTAssertFalse(checker.osUpgradeCapability.canUpgradeOS)
    }

    func testWhenModelSupportsNewerVersionThenIsCapable() {
        let checker = SupportedOSChecker(currentOSMajorVersion: 15, hardwareModel: "iPhone10,1")
        XCTAssertEqual(checker.osUpgradeCapability, .capable)
        XCTAssertTrue(checker.osUpgradeCapability.canUpgradeOS)
    }

    func testWhenModelIsOnItsMaxVersionThenIsIncapable() {
        let checker = SupportedOSChecker(currentOSMajorVersion: 16, hardwareModel: "iPhone10,1")
        XCTAssertEqual(checker.osUpgradeCapability, .incapable)
    }

    func testWhenModelIsNotInTableThenIsCapable() {
        let checker = SupportedOSChecker(currentOSMajorVersion: 15, hardwareModel: "iPhone14,7")
        XCTAssertEqual(checker.osUpgradeCapability, .capable)
    }

    func testWhenModelIsUnavailableThenIsUnknownAndTreatedAsCapable() {
        let checker = SupportedOSChecker(currentOSMajorVersion: 15, hardwareModel: nil)
        XCTAssertEqual(checker.osUpgradeCapability, .unknown)
        XCTAssertTrue(checker.osUpgradeCapability.canUpgradeOS)
    }

    func testWhenCustomTableIsProvidedThenItIsUsed() {
        let checker = SupportedOSChecker(currentOSMajorVersion: 17,
                                         hardwareModel: "iPhone11,2",
                                         maxSupportedVersionByModel: ["iPhone11,2": 17])
        XCTAssertEqual(checker.osUpgradeCapability, .incapable)
    }

    // MARK: - OSUpgradeCapabilityOverridePersistor

    func testWhenNoOverrideIsStoredThenHardwareValueIsUsed() {
        let persistor = OSUpgradeCapabilityOverridePersistor(keyValueStore: MockKeyValueStore())
        XCTAssertEqual(persistor.current, .default)
        XCTAssertTrue(persistor.canUpgradeOS(default: true))
        XCTAssertFalse(persistor.canUpgradeOS(default: false))
    }

    func testWhenOverrideIsForcedThenItWinsOverHardwareValue() {
        let persistor = OSUpgradeCapabilityOverridePersistor(keyValueStore: MockKeyValueStore())

        persistor.current = .forceIncapable
        XCTAssertFalse(persistor.canUpgradeOS(default: true))

        persistor.current = .forceCapable
        XCTAssertTrue(persistor.canUpgradeOS(default: false))
    }

    func testWhenOverrideIsResetToDefaultThenStoredValueIsRemoved() {
        let keyValueStore = MockKeyValueStore()
        let persistor = OSUpgradeCapabilityOverridePersistor(keyValueStore: keyValueStore)

        persistor.current = .forceIncapable
        persistor.current = .default

        XCTAssertNil(keyValueStore.object(forKey: OSUpgradeCapabilityOverridePersistor.Key.override.rawValue))
    }
}
