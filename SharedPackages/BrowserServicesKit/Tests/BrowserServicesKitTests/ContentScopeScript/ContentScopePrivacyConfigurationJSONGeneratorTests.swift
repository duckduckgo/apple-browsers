//
//  ContentScopePrivacyConfigurationJSONGeneratorTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import BrowserServicesKit
import PrivacyConfig
import PrivacyConfigTestsUtils

final class ContentScopePrivacyConfigurationJSONGeneratorTests: XCTestCase {

    private func makeManager(features: [String: Any] = [:]) -> MockPrivacyConfigurationManager {
        var baseConfig: [String: Any] = [
            "version": 1,
            "features": features,
            "unprotectedTemporary": []
        ]

        let manager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration())
        manager.currentConfigString = jsonString(from: baseConfig)
        return manager
    }

    private func generatedJSON(from manager: MockPrivacyConfigurationManager, isSurrogateInjectionDisabled: Bool = false) -> [String: Any]? {
        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(),
                                                                       privacyConfigurationManager: manager,
                                                                       isSurrogateInjectionDisabled: isSurrogateInjectionDisabled)
        guard let data = generator.privacyConfiguration,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func generatedFeatures(from manager: MockPrivacyConfigurationManager, isSurrogateInjectionDisabled: Bool = false) -> [String: Any]? {
        generatedJSON(from: manager, isSurrogateInjectionDisabled: isSurrogateInjectionDisabled)?["features"] as? [String: Any]
    }

    private func jsonString(from dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // MARK: - Autoconsent exclusion

    func testWhenAutoconsentPresentThenItIsExcludedFromOutput() {
        let features: [String: Any] = [
            "autoconsent": ["state": "enabled", "exceptions": []],
            "contentBlocking": ["state": "enabled", "exceptions": []]
        ]
        let manager = makeManager(features: features)

        guard let outputFeatures = generatedFeatures(from: manager) else {
            XCTFail("Could not generate config")
            return
        }

        XCTAssertNil(outputFeatures["autoconsent"], "autoconsent must be excluded from C-S-S config")
        XCTAssertNotNil(outputFeatures["contentBlocking"], "other features must still be present")
    }

    // MARK: - eventHub exclusion

    func testWhenEventHubPresentThenItIsExcludedFromOutput() {
        let features: [String: Any] = [
            "eventHub": ["state": "enabled", "exceptions": []],
            "contentBlocking": ["state": "enabled", "exceptions": []]
        ]
        let manager = makeManager(features: features)

        guard let outputFeatures = generatedFeatures(from: manager) else {
            XCTFail("Could not generate config")
            return
        }

        XCTAssertNil(outputFeatures["eventHub"], "eventHub is read natively only and must be excluded from C-S-S config")
        XCTAssertNotNil(outputFeatures["contentBlocking"], "other features must still be present")
    }

    // MARK: - trackerAllowlist excluded

    func testWhenTrackerAllowlistPresentThenItIsExcluded() {
        let features: [String: Any] = [
            "contentBlocking": ["state": "enabled", "exceptions": []]
        ]
        let manager = makeManager(features: features)

        guard let outputFeatures = generatedFeatures(from: manager) else {
            XCTFail("Could not generate config")
            return
        }

        XCTAssertNil(outputFeatures["trackerAllowlist"], "trackerAllowlist must be excluded (not needed by isolated script)")
        XCTAssertNil(outputFeatures["autoconsent"])
    }

    // MARK: - Surrogate injection

    private func trackerProtectionSettings(from manager: MockPrivacyConfigurationManager,
                                           isSurrogateInjectionDisabled: Bool) -> [String: Any]? {
        let features = generatedFeatures(from: manager, isSurrogateInjectionDisabled: isSurrogateInjectionDisabled)
        return (features?["trackerProtection"] as? [String: Any])?["settings"] as? [String: Any]
    }

    func testWhenSurrogateInjectionDisabledThenSettingIsDisabledAndOtherSettingsKept() {
        let manager = makeManager(features: [
            "trackerProtection": ["state": "enabled", "exceptions": [], "settings": ["additionalCheck": "enabled"]]
        ])

        let settings = trackerProtectionSettings(from: manager, isSurrogateInjectionDisabled: true)

        XCTAssertEqual(settings?["surrogateInjection"] as? String, "disabled")
        XCTAssertEqual(settings?["additionalCheck"] as? String, "enabled")
    }

    func testWhenSurrogateInjectionDisabledAndTrackerProtectionHasNoSettingsThenSettingIsAdded() {
        let manager = makeManager(features: ["trackerProtection": ["state": "enabled", "exceptions": []]])

        let settings = trackerProtectionSettings(from: manager, isSurrogateInjectionDisabled: true)

        XCTAssertEqual(settings?["surrogateInjection"] as? String, "disabled")
    }

    func testWhenSurrogateInjectionNotDisabledThenSettingIsLeftAlone() {
        let manager = makeManager(features: [
            "trackerProtection": ["state": "enabled", "exceptions": [], "settings": ["surrogateInjection": "enabled"]]
        ])

        let settings = trackerProtectionSettings(from: manager, isSurrogateInjectionDisabled: false)

        XCTAssertEqual(settings?["surrogateInjection"] as? String, "enabled")
    }

    func testWhenConfigChangesThenPatchedConfigReflectsNewConfig() {
        let manager = makeManager(features: [
            "trackerProtection": ["state": "enabled", "exceptions": [], "settings": ["additionalCheck": "enabled"]]
        ])
        XCTAssertEqual(trackerProtectionSettings(from: manager, isSurrogateInjectionDisabled: true)?["additionalCheck"] as? String, "enabled")

        let updated = makeManager(features: [
            "trackerProtection": ["state": "enabled", "exceptions": [], "settings": ["additionalCheck": "disabled"]]
        ])
        let settings = trackerProtectionSettings(from: updated, isSurrogateInjectionDisabled: true)

        XCTAssertEqual(settings?["additionalCheck"] as? String, "disabled", "a cached patch must not outlive the config it came from")
        XCTAssertEqual(settings?["surrogateInjection"] as? String, "disabled")
    }

    func testWhenSurrogateInjectionDisabledThenOtherFeaturesAreUnchanged() {
        let manager = makeManager(features: [
            "trackerProtection": ["state": "enabled", "exceptions": []],
            "contentBlocking": ["state": "enabled", "exceptions": []],
            "autoconsent": ["state": "enabled", "exceptions": []]
        ])
        guard let features = generatedFeatures(from: manager, isSurrogateInjectionDisabled: true) else {
            XCTFail("Could not generate config")
            return
        }

        XCTAssertNotNil(features["contentBlocking"])
        XCTAssertNil(features["autoconsent"], "excluded features must stay excluded")
    }

    // MARK: - Nil on bad input

    func testWhenConfigIsInvalidThenReturnsNil() {
        let manager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration())
        manager.currentConfigString = "not valid json"

        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        XCTAssertNil(generator.privacyConfiguration)
    }
}
