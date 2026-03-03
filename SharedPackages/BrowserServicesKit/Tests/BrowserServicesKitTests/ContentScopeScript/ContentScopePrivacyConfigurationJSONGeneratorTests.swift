//
//  ContentScopePrivacyConfigurationJSONGeneratorTests.swift
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

import XCTest
@testable import BrowserServicesKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import TrackerRadarKit

final class ContentScopePrivacyConfigurationJSONGeneratorTests: XCTestCase {

    private func makeManager(
        configJSON: [String: Any] = [:],
        contentBlockingEnabled: Bool = true,
        tempUnprotectedDomains: [String] = [],
        userUnprotectedDomains: [String] = [],
        trackerAllowlist: PrivacyConfigurationData.TrackerAllowlist? = nil,
        contentBlockingExceptions: [String] = []
    ) -> (MockPrivacyConfigurationManager, MockPrivacyConfiguration) {
        let config = MockPrivacyConfiguration()
        config.isFeatureEnabledCheck = { feature, _ in
            if feature == .contentBlocking { return contentBlockingEnabled }
            return true
        }
        config.tempUnprotectedDomains = tempUnprotectedDomains
        config.userUnprotectedDomains = userUnprotectedDomains
        if let allowlist = trackerAllowlist {
            config.trackerAllowlist = allowlist
        }
        config.exceptionsListClosure = { feature in
            if feature == .contentBlocking { return contentBlockingExceptions }
            return []
        }

        let manager = MockPrivacyConfigurationManager(privacyConfig: config)

        var baseConfig: [String: Any] = ["version": 1, "features": [:], "unprotectedTemporary": []]
        for (key, value) in configJSON {
            baseConfig[key] = value
        }
        manager.currentConfigString = jsonString(from: baseConfig)

        return (manager, config)
    }

    private func makeDataSource(encodedData: String? = "{}", surrogatesText: String? = nil) -> MockTrackerProtectionDataSource {
        MockTrackerProtectionDataSource(encodedTrackerData: encodedData, surrogatesText: surrogatesText)
    }

    private func generatedFeatures(from generator: ContentScopePrivacyConfigurationJSONGenerator) -> [String: Any]? {
        guard let data = generator.privacyConfiguration,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [String: Any] else {
            return nil
        }
        return features
    }

    private func trackerProtectionSettings(from generator: ContentScopePrivacyConfigurationJSONGenerator) -> [String: Any]? {
        guard let features = generatedFeatures(from: generator),
              let tp = features["trackerProtection"] as? [String: Any],
              let settings = tp["settings"] as? [String: Any] else {
            return nil
        }
        return settings
    }

    private func jsonString(from dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // MARK: - Enable/disable matrix (Item 1)

    func testTPAbsentAndCBEnabled_defaultsToEnabled() {
        let (manager, _) = makeManager(contentBlockingEnabled: true)
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        guard let features = generatedFeatures(from: generator),
              let tp = features["trackerProtection"] as? [String: Any] else {
            XCTFail("trackerProtection feature missing")
            return
        }
        XCTAssertEqual(tp["state"] as? String, "enabled")

        let settings = tp["settings"] as? [String: Any]
        XCTAssertEqual(settings?["blockingEnabled"] as? Bool, true)
    }

    func testTPDisabledAndCBEnabled() {
        let features: [String: Any] = [
            "trackerProtection": ["state": "disabled", "exceptions": []]
        ]
        let (manager, _) = makeManager(configJSON: ["features": features], contentBlockingEnabled: true)
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        guard let generatedFeatures = generatedFeatures(from: generator),
              let tp = generatedFeatures["trackerProtection"] as? [String: Any] else {
            XCTFail("trackerProtection feature missing")
            return
        }
        XCTAssertEqual(tp["state"] as? String, "disabled")
    }

    func testTPEnabledAndCBDisabled() {
        let features: [String: Any] = [
            "trackerProtection": ["state": "enabled", "exceptions": []]
        ]
        let (manager, _) = makeManager(configJSON: ["features": features], contentBlockingEnabled: false)
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["blockingEnabled"] as? Bool, false)
    }

    func testBothDisabled() {
        let features: [String: Any] = [
            "trackerProtection": ["state": "disabled", "exceptions": []]
        ]
        let (manager, _) = makeManager(configJSON: ["features": features], contentBlockingEnabled: false)
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        guard let generatedFeatures = generatedFeatures(from: generator),
              let tp = generatedFeatures["trackerProtection"] as? [String: Any] else {
            XCTFail("trackerProtection feature missing")
            return
        }
        XCTAssertEqual(tp["state"] as? String, "disabled")

        let settings = tp["settings"] as? [String: Any]
        XCTAssertEqual(settings?["blockingEnabled"] as? Bool, false)
    }

    // MARK: - CTL setting (Item 3)

    func testCTLEnabledFalseByDefault() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["ctlEnabled"] as? Bool, false)
    }

    func testCTLEnabledPassedThrough() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource(),
            ctlEnabled: true
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["ctlEnabled"] as? Bool, true)
    }

    // MARK: - Unprotected domains (Item 2)

    func testUnprotectedDomainsIncluded() {
        let (manager, _) = makeManager(
            tempUnprotectedDomains: ["temp.com"],
            userUnprotectedDomains: ["user.com"]
        )
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["tempUnprotectedDomains"] as? [String], ["temp.com"])
        XCTAssertEqual(settings?["userUnprotectedDomains"] as? [String], ["user.com"])
    }

    func testContentBlockingExceptionsIncluded() {
        let (manager, _) = makeManager(contentBlockingExceptions: ["exception.com"])
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["contentBlockingExceptions"] as? [String], ["exception.com"])
    }

    // MARK: - Surrogates passthrough

    func testSurrogatesTextIncludedInSettings() {
        let surrogates = "google-analytics.com/ga.js application/javascript\n(function() {})();\n"
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource(surrogatesText: surrogates)
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["surrogates"] as? String, surrogates)
    }

    func testNilSurrogatesOmitsSurrogatesSetting() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource(surrogatesText: nil)
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertNil(settings?["surrogates"])
    }

    // MARK: - No data source

    func testNoDataSourceOmitsTrackerProtection() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: nil
        )

        guard let features = generatedFeatures(from: generator) else {
            XCTFail("Could not generate config")
            return
        }
        XCTAssertNil(features["trackerProtection"])
    }
}

// MARK: - Test Helpers

private struct MockTrackerProtectionDataSource: TrackerProtectionDataSource {
    var trackerData: TrackerRadarKit.TrackerData? { nil }
    let encodedTrackerData: String?
    let surrogatesText: String?

    init(encodedTrackerData: String? = "{}", surrogatesText: String? = nil) {
        self.encodedTrackerData = encodedTrackerData
        self.surrogatesText = surrogatesText
    }
}
