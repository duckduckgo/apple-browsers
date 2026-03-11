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

    private func makeDataSource(encodedData: String? = "{}") -> MockTrackerProtectionDataSource {
        MockTrackerProtectionDataSource(encodedTrackerData: encodedData)
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

    // MARK: - Surrogates and trackerData removed (bundled/passed via args)

    func testSurrogatesAndTrackerDataNeverWrittenToSettings() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertNil(settings?["surrogates"], "surrogates must not appear in trackerProtection settings")
        XCTAssertNil(settings?["trackerData"], "trackerData must not appear in trackerProtection settings (passed via args)")
        XCTAssertNotNil(settings?["blockingEnabled"], "blockingEnabled should still be present")
        XCTAssertNotNil(settings?["ctlEnabled"], "ctlEnabled should still be present")
    }

    // MARK: - P0-10: CTL platform behavior

    func testCTLEnabledFalse_settingsReflectDisabled() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource(),
            ctlEnabled: false
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["ctlEnabled"] as? Bool, false,
                       "iOS platform should always pass ctlEnabled=false")
    }

    func testCTLEnabledTrue_settingsReflectEnabled() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource(),
            ctlEnabled: true
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["ctlEnabled"] as? Bool, true,
                       "macOS platform should pass ctlEnabled reflecting live state")
    }

    func testCTLDefault_isFalse() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["ctlEnabled"] as? Bool, false,
                       "Default ctlEnabled should be false (iOS behavior)")
    }

    // MARK: - Settings shape guard

    func testTrackerProtectionSettings_containOnlyExpectedKeys() {
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource()
        )

        // trackerData is now passed via ContentScopeProperties (args.trackerData),
        // not via feature settings
        let expectedKeys: Set<String> = [
            "allowlist", "tempUnprotectedDomains",
            "userUnprotectedDomains", "contentBlockingExceptions",
            "blockingEnabled", "ctlEnabled"
        ]

        guard let settings = trackerProtectionSettings(from: generator) else {
            XCTFail("trackerProtection settings missing")
            return
        }

        let actualKeys = Set(settings.keys)
        XCTAssertEqual(actualKeys, expectedKeys,
                       "trackerProtection settings keys should match expected set exactly")
        XCTAssertFalse(actualKeys.contains("surrogates"),
                       "surrogates must never appear in trackerProtection settings")
        XCTAssertFalse(actualKeys.contains("trackerData"),
                       "trackerData must never appear in trackerProtection settings (passed via args)")
    }

    // MARK: - CTL-disabled regression guard

    func testCTLRulesPresent_ctlDisabled_settingsStillPassCtlDisabled() {
        let ctlTrackerData = """
        {"trackers":{"facebook.net":{"domain":"facebook.net","owner":{"name":"Facebook"},"default":"ignore","rules":[{"rule":"facebook\\\\.net/.*sdk\\\\.js","action":"block-ctl-fb"}]}},"entities":{"Facebook":{"domains":["facebook.net"]}},"domains":{"facebook.net":"Facebook"}}
        """
        let (manager, _) = makeManager()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: makeDataSource(encodedData: ctlTrackerData),
            ctlEnabled: false
        )

        let settings = trackerProtectionSettings(from: generator)
        XCTAssertEqual(settings?["ctlEnabled"] as? Bool, false,
                       "ctlEnabled must be false even when CTL rules are in the payload")
        // trackerData is now passed via ContentScopeProperties, not feature settings
        XCTAssertNil(settings?["trackerData"],
                     "trackerData must not appear in settings (passed via args.trackerData)")
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

    func testAllowlistRules_areEscapedForRegex() {
        // Allowlist rules are passed to JavaScript's .match() which treats them as regex.
        // Dots and other special chars must be escaped to prevent wildcards.
        let allowlist = PrivacyConfigurationData.TrackerAllowlist(entries: [
            "example.com": [
                PrivacyConfigurationData.TrackerAllowlist.Entry(
                    rule: "facebook.com/tracker.js",
                    domains: ["<all>"]
                )
            ]
        ], state: PrivacyConfigurationData.State.enabled)

        let (manager, _) = makeManager(trackerAllowlist: allowlist)
        let dataSource = MockTrackerProtectionDataSource()
        let generator = ContentScopePrivacyConfigurationJSONGenerator(
            featureFlagger: MockFeatureFlagger(),
            privacyConfigurationManager: manager,
            trackerProtectionDataSource: dataSource
        )

        guard let features = generatedFeatures(from: generator),
              let tp = features["trackerProtection"] as? [String: Any],
              let settings = tp["settings"] as? [String: Any],
              let allowlistDict = settings["allowlist"] as? [String: [[String: Any]]],
              let entries = allowlistDict["example.com"],
              let firstEntry = entries.first,
              let rule = firstEntry["rule"] as? String else {
            XCTFail("Could not extract allowlist rule")
            return
        }

        // Verify dots are escaped
        XCTAssertEqual(rule, "facebook\\.com/tracker\\.js", "Dots should be escaped for regex matching")
        XCTAssertFalse(rule.contains("facebook.com"), "Original unescaped dots should not be present")
    }
}

// MARK: - Test Helpers

private struct MockTrackerProtectionDataSource: TrackerProtectionDataSource {
    var trackerData: TrackerRadarKit.TrackerData? { nil }
    let encodedTrackerData: String?

    init(encodedTrackerData: String? = "{}") {
        self.encodedTrackerData = encodedTrackerData
    }
}
