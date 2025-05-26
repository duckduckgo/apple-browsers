//
//  MaliciousSiteProtectionFeatureFlagsTests.swift
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
import XCTest

@testable import MaliciousSiteProtection

class MaliciousSiteProtectionFeatureFlagsTests: XCTestCase {
    private var sut: MaliciousSiteProtectionFeatureFlags!
    private var isFeatureEnabled: Bool = false
    private var isScamProtectionEnabled: Bool = false
    private var configurationManagerMock: PrivacyConfigurationManagerMock!

    override func setUp() {
        configurationManagerMock = PrivacyConfigurationManagerMock()
        sut = MaliciousSiteProtectionFeatureFlags(privacyConfigManager: configurationManagerMock, isMaliciousSiteProtectionEnabled: { [unowned self] in isFeatureEnabled })
    }

    // MARK: - Web Error Page

    func testWhenThreatDetectionEnabled_AndFeatureFlagIsOn_ThenReturnTrue() throws {
        // GIVEN
        isFeatureEnabled = true

        // WHEN
        let result = sut.isMaliciousSiteProtectionEnabled

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenThreatDetectionEnabled_AndFeatureFlagIsOff_ThenReturnFalse() throws {
        // GIVEN
        isFeatureEnabled = false

        // WHEN
        let result = sut.isMaliciousSiteProtectionEnabled

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenThreatDetectionEnabledForDomain_AndFeatureIsAvailableForDomain_ThenReturnTrue() throws {
        // GIVEN
        isFeatureEnabled = true
        let privacyConfigMock = configurationManagerMock.privacyConfig as! PrivacyConfigurationMock
        privacyConfigMock.enabledFeatures = [.maliciousSiteProtection: ["example.com"]]
        let domain = "example.com"

        // WHEN
        let result = sut.shouldDetectMaliciousThreat(forDomain: domain)

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenThreatDetectionCalledEnabledForDomain_AndFeatureIsNotAvailableForDomain_ThenReturnFalse() throws {
        // GIVEN
        isFeatureEnabled = true
        let privacyConfigMock = configurationManagerMock.privacyConfig as! PrivacyConfigurationMock
        privacyConfigMock.enabledFeatures = [.maliciousSiteProtection: []]
        let domain = "example.com"

        // WHEN
        let result = sut.shouldDetectMaliciousThreat(forDomain: domain)

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenThreatDetectionEnabledForDomain_AndPrivacyConfigFeatureFlagIsOn_AndThreatDetectionSubFeatureIsOff_ThenReturnTrue() throws {
        // GIVEN
        let privacyConfigMock = configurationManagerMock.privacyConfig as! PrivacyConfigurationMock
        privacyConfigMock.enabledFeatures = [.adClickAttribution: ["example.com"]]
        let domain = "example.com"

        // WHEN
        let result = sut.shouldDetectMaliciousThreat(forDomain: domain)

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenSettingIsDefinedReturnValue() throws {
        // GIVEN
        let privacyConfigMock = configurationManagerMock.privacyConfig as! PrivacyConfigurationMock
        privacyConfigMock.settings[.maliciousSiteProtection] = [
            MaliciousSiteProtectionFeatureSettings.hashPrefixUpdateFrequency.rawValue: 10,
            MaliciousSiteProtectionFeatureSettings.filterSetUpdateFrequency.rawValue: 50
        ]
        sut = MaliciousSiteProtectionFeatureFlags(privacyConfigManager: configurationManagerMock, isMaliciousSiteProtectionEnabled: { [unowned self] in isFeatureEnabled })

        // WHEN
        let hashPrefixUpdateFrequency = sut.hashPrefixUpdateFrequency
        let filterSetUpdateFrequency = sut.filterSetUpdateFrequency

        // THEN
        XCTAssertEqual(hashPrefixUpdateFrequency, 10)
        XCTAssertEqual(filterSetUpdateFrequency, 50)
    }

    func testWhenSettingIsNotDefinedReturnDefaultValue() throws {
        // GIVEN
        let privacyConfigMock = configurationManagerMock.privacyConfig as! PrivacyConfigurationMock
        privacyConfigMock.settings[.maliciousSiteProtection] = [:]
        sut = MaliciousSiteProtectionFeatureFlags(privacyConfigManager: configurationManagerMock, isMaliciousSiteProtectionEnabled: { [unowned self] in isFeatureEnabled })

        // WHEN
        let hashPrefixUpdateFrequency = sut.hashPrefixUpdateFrequency
        let filterSetUpdateFrequency = sut.filterSetUpdateFrequency

        // THEN
        XCTAssertEqual(hashPrefixUpdateFrequency, 20)
        XCTAssertEqual(filterSetUpdateFrequency, 720)
    }

}
