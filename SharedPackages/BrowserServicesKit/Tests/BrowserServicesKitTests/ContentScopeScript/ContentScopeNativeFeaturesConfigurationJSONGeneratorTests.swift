//
//  ContentScopeNativeFeaturesConfigurationJSONGeneratorTests.swift
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
@testable import BrowserServicesKit

final class ContentScopeNativeFeaturesConfigurationJSONGeneratorTests: XCTestCase {

    private struct FixedGenerator: CustomisedPrivacyConfigurationJSONGenerating {
        let privacyConfiguration: Data?
    }

    private func base(_ object: [String: Any]) throws -> FixedGenerator {
        FixedGenerator(privacyConfiguration: try JSONSerialization.data(withJSONObject: object))
    }

    private func json(_ generator: ContentScopeNativeFeaturesConfigurationJSONGenerator) throws -> [String: Any] {
        let data = try XCTUnwrap(generator.privacyConfiguration)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInjectedFeatureIsEnabledWithItsSettingsAndOtherFeaturesAreKept() throws {
        let generator = ContentScopeNativeFeaturesConfigurationJSONGenerator(
            base: try base(["version": 1, "features": ["gpc": ["state": "enabled", "exceptions": []]], "unprotectedTemporary": []]),
            features: ["nativeFeature": ["token": "abc", "flag": true]]
        )

        let output = try json(generator)
        let features = try XCTUnwrap(output["features"] as? [String: Any])
        let injected = try XCTUnwrap(features["nativeFeature"] as? [String: Any])
        XCTAssertEqual(injected["state"] as? String, "enabled")
        XCTAssertEqual((injected["exceptions"] as? [Any])?.count, 0)
        let settings = try XCTUnwrap(injected["settings"] as? [String: Any])
        XCTAssertEqual(settings["token"] as? String, "abc")
        XCTAssertEqual(settings["flag"] as? Bool, true)
        XCTAssertNotNil(features["gpc"])
        XCTAssertEqual(output["version"] as? Int, 1)
    }

    func testInjectedFeatureReplacesRemoteEntryOfTheSameName() throws {
        let generator = ContentScopeNativeFeaturesConfigurationJSONGenerator(
            base: try base(["features": ["nativeFeature": ["state": "disabled", "exceptions": [["domain": "example.com"]]]]]),
            features: ["nativeFeature": ["token": "abc"]]
        )

        let features = try XCTUnwrap(try json(generator)["features"] as? [String: Any])
        let injected = try XCTUnwrap(features["nativeFeature"] as? [String: Any])
        XCTAssertEqual(injected["state"] as? String, "enabled")
        XCTAssertEqual((injected["exceptions"] as? [Any])?.count, 0)
    }

    func testWithoutInjectedFeaturesTheBaseConfigurationIsReturnedUnchanged() throws {
        let baseGenerator = try base(["features": [:]])
        let generator = ContentScopeNativeFeaturesConfigurationJSONGenerator(base: baseGenerator, features: [:])

        XCTAssertEqual(generator.privacyConfiguration, baseGenerator.privacyConfiguration)
    }

    func testWhenTheBaseProducesNothingThenTheFallbackConfigurationIsExtended() throws {
        let fallback = try JSONSerialization.data(withJSONObject: ["features": ["gpc": ["state": "enabled"]], "unprotectedTemporary": []])
        let generator = ContentScopeNativeFeaturesConfigurationJSONGenerator(base: FixedGenerator(privacyConfiguration: nil),
                                                                              fallbackConfiguration: fallback,
                                                                              features: ["nativeFeature": [:]])

        let features = try XCTUnwrap(try json(generator)["features"] as? [String: Any])
        XCTAssertNotNil(features["gpc"])
        XCTAssertNotNil(features["nativeFeature"])
    }

    func testUnreadableConfigurationStillCarriesTheInjectedFeatures() throws {
        let generator = ContentScopeNativeFeaturesConfigurationJSONGenerator(base: FixedGenerator(privacyConfiguration: nil),
                                                                              fallbackConfiguration: Data(),
                                                                              features: ["nativeFeature": ["token": "abc"]])

        let output = try json(generator)
        let features = try XCTUnwrap(output["features"] as? [String: Any])
        XCTAssertNotNil(features["nativeFeature"])
        XCTAssertEqual((output["unprotectedTemporary"] as? [Any])?.count, 0)
    }
}
