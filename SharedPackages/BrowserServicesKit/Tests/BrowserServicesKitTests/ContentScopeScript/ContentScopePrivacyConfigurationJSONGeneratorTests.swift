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

    // MARK: - Nil on bad input

    func testWhenConfigIsInvalidThenReturnsNil() {
        let manager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration())
        manager.currentConfigString = "not valid json"

        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        XCTAssertNil(generator.privacyConfiguration)
    }

    // MARK: - Caching

    func testWhenConfigIsUnchangedThenGeneratedJSONIsReusedFromCache() {
        let manager = makeManager(features: ["cachingTestUnchanged": ["state": "enabled", "exceptions": []]])
        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)

        let first = generator.privacyConfiguration
        XCTAssertNotNil(first)
        XCTAssertEqual(ContentScopePrivacyConfigurationJSONGenerator.cache.value(for: manager.currentConfig,
                                                                                 excludedFeatures: ContentScopePrivacyConfigurationJSONGenerator.defaultExcludedFeatures),
                       first)

        let otherGenerator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        XCTAssertEqual(otherGenerator.privacyConfiguration, first)
    }

    func testWhenCacheHasEntryForConfigThenGeneratorReturnsItWithoutRegenerating() {
        let manager = makeManager(features: ["cachingTestSentinel": ["state": "enabled", "exceptions": []]])
        let sentinel = Data("cached".utf8)
        ContentScopePrivacyConfigurationJSONGenerator.cache.store(sentinel,
                                                                  for: manager.currentConfig,
                                                                  excludedFeatures: ContentScopePrivacyConfigurationJSONGenerator.defaultExcludedFeatures)

        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        XCTAssertEqual(generator.privacyConfiguration, sentinel)
    }

    func testWhenConfigChangesThenNewConfigIsGenerated() {
        let manager = makeManager(features: ["cachingTestBefore": ["state": "enabled", "exceptions": []]])
        XCTAssertNotNil(generatedFeatures(from: manager)?["cachingTestBefore"])

        manager.currentConfigString = jsonString(from: [
            "version": 2,
            "features": ["cachingTestAfter": ["state": "enabled", "exceptions": []]],
            "unprotectedTemporary": []
        ])

        let outputFeatures = generatedFeatures(from: manager)
        XCTAssertNil(outputFeatures?["cachingTestBefore"])
        XCTAssertNotNil(outputFeatures?["cachingTestAfter"])
    }

    func testWhenExcludedFeaturesDifferThenEachGeneratorGetsItsOwnOutput() {
        let features: [String: Any] = [
            "autoconsent": ["state": "enabled", "exceptions": []],
            "cachingTestExclusions": ["state": "enabled", "exceptions": []]
        ]
        let manager = makeManager(features: features)

        let defaultGenerator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        let customGenerator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(),
                                                                            privacyConfigurationManager: manager,
                                                                            excludedFeatures: [PrivacyFeature.eventHub.rawValue])

        let defaultFeatures = defaultGenerator.privacyConfiguration.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["features"] as? [String: Any]
        let customFeatures = customGenerator.privacyConfiguration.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["features"] as? [String: Any]

        XCTAssertNil(defaultFeatures?["autoconsent"])
        XCTAssertNotNil(customFeatures?["autoconsent"])
        XCTAssertNotNil(defaultFeatures?["cachingTestExclusions"])
        XCTAssertNotNil(customFeatures?["cachingTestExclusions"])
    }

    func testWhenConfigBecomesValidThenItIsGenerated() {
        let manager = MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration())
        manager.currentConfigString = "not valid json either"
        let generator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: MockFeatureFlagger(), privacyConfigurationManager: manager)
        XCTAssertNil(generator.privacyConfiguration)

        manager.currentConfigString = jsonString(from: [
            "version": 1,
            "features": ["cachingTestRecovered": ["state": "enabled", "exceptions": []]],
            "unprotectedTemporary": []
        ])
        XCTAssertNotNil(generatedFeatures(from: manager)?["cachingTestRecovered"])
    }
}
