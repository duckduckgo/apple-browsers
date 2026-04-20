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

    private func generatedJSON(from manager: MockPrivacyConfigurationManager) -> [String: Any]? {
        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        guard let data = generator.privacyConfiguration,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func generatedFeatures(from manager: MockPrivacyConfigurationManager) -> [String: Any]? {
        generatedJSON(from: manager)?["features"] as? [String: Any]
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

    func testWhenAutoconsentAbsentThenOutputIsUnchanged() {
        let features: [String: Any] = [
            "contentBlocking": ["state": "enabled", "exceptions": []],
            "trackerProtection": ["state": "enabled", "exceptions": []]
        ]
        let manager = makeManager(features: features)

        guard let outputFeatures = generatedFeatures(from: manager) else {
            XCTFail("Could not generate config")
            return
        }

        XCTAssertNotNil(outputFeatures["contentBlocking"])
        XCTAssertNotNil(outputFeatures["trackerProtection"])
        XCTAssertNil(outputFeatures["autoconsent"])
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

    // MARK: - Version preserved

    func testWhenConfigHasVersionThenItIsPreserved() {
        let manager = makeManager()

        guard let json = generatedJSON(from: manager) else {
            XCTFail("Could not generate config")
            return
        }

        XCTAssertNotNil(json["version"])
    }

    // MARK: - Nil on bad input

    func testWhenConfigIsInvalidThenReturnsNil() {
        let manager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration())
        manager.currentConfigString = "not valid json"

        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        XCTAssertNil(generator.privacyConfiguration)
    }
}
