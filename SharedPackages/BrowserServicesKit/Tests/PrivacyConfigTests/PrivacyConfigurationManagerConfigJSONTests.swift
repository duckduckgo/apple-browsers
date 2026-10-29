//
//  PrivacyConfigurationManagerConfigJSONTests.swift
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
import PrivacyConfigTestsUtils
import PrivacyConfig

final class PrivacyConfigurationManagerConfigJSONTests: XCTestCase {

    private func configData(version: Int, features: [String: Any]) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: ["version": version, "features": features, "unprotectedTemporary": []])
    }

    private func makeManager(embedded: Data) -> PrivacyConfigurationManager {
        PrivacyConfigurationManager(fetchedETag: nil,
                                    fetchedData: nil,
                                    embeddedDataProvider: MockEmbeddedDataProvider(data: embedded, etag: "embedded"),
                                    localProtection: MockDomainsProtectionStore(),
                                    internalUserDecider: MockInternalUserDecider())
    }

    private func features(in json: Data?) -> [String: Any]? {
        guard let json, let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        return object["features"] as? [String: Any]
    }

    func testWhenConfigIsUnchangedThenJSONIsEncodedOnce() {
        let manager = makeManager(embedded: configData(version: 1, features: ["gpc": ["state": "enabled", "exceptions": []]]))

        let first = manager.currentConfigJSON(excludingFeatures: [])
        let second = manager.currentConfigJSON(excludingFeatures: [])

        XCTAssertNotNil(features(in: first)?["gpc"])
        XCTAssertEqual(first, second)
        // The same buffer is handed back, not an equal re-encoding.
        XCTAssertEqual(first?.withUnsafeBytes { $0.baseAddress }, second?.withUnsafeBytes { $0.baseAddress })
    }

    func testWhenConfigIsReloadedThenNewJSONIsEncoded() {
        let manager = makeManager(embedded: configData(version: 1, features: ["before": ["state": "enabled", "exceptions": []]]))
        XCTAssertNotNil(features(in: manager.currentConfigJSON(excludingFeatures: []))?["before"])

        manager.reload(etag: "fetched", data: configData(version: 2, features: ["after": ["state": "enabled", "exceptions": []]]))

        let reloaded = features(in: manager.currentConfigJSON(excludingFeatures: []))
        XCTAssertNil(reloaded?["before"])
        XCTAssertNotNil(reloaded?["after"])
    }

    func testWhenReloadFallsBackToEmbeddedThenEmbeddedJSONIsEncoded() {
        let manager = makeManager(embedded: configData(version: 1, features: ["embedded": ["state": "enabled", "exceptions": []]]))
        manager.reload(etag: "fetched", data: configData(version: 2, features: ["fetched": ["state": "enabled", "exceptions": []]]))
        XCTAssertNotNil(features(in: manager.currentConfigJSON(excludingFeatures: []))?["fetched"])

        XCTAssertEqual(manager.reload(etag: "broken", data: Data("not json".utf8)), .embeddedFallback)

        let fallback = features(in: manager.currentConfigJSON(excludingFeatures: []))
        XCTAssertNil(fallback?["fetched"])
        XCTAssertNotNil(fallback?["embedded"])
    }

    func testWhenExcludedFeaturesDifferThenEachGetsItsOwnJSON() {
        let manager = makeManager(embedded: configData(version: 1, features: [
            "autoconsent": ["state": "enabled", "exceptions": []],
            "gpc": ["state": "enabled", "exceptions": []]
        ]))

        let all = features(in: manager.currentConfigJSON(excludingFeatures: []))
        let withoutAutoconsent = features(in: manager.currentConfigJSON(excludingFeatures: ["autoconsent"]))

        XCTAssertNotNil(all?["autoconsent"])
        XCTAssertNil(withoutAutoconsent?["autoconsent"])
        XCTAssertNotNil(withoutAutoconsent?["gpc"])
    }
}
