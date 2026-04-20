//
//  TrackerProtectionSubfeatureTests.swift
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

final class TrackerProtectionSubfeatureTests: XCTestCase {

    // MARK: - Feature Name

    func testWhenFeatureNameIsAccessedThenItMatchesJavaScriptFeatureName() {
        let subfeature = TrackerProtectionSubfeature()
        XCTAssertEqual(subfeature.featureName, "trackerProtection")
        XCTAssertEqual(TrackerProtectionSubfeature.featureNameValue, "trackerProtection")
    }

    // MARK: - Handler Registration

    func testWhenResourceObservedMethodIsRequestedThenHandlerIsReturned() {
        let subfeature = TrackerProtectionSubfeature()
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "resourceObserved"))
    }

    func testWhenSurrogateInjectedMethodIsRequestedThenHandlerIsReturned() {
        let subfeature = TrackerProtectionSubfeature()
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "surrogateInjected"))
    }

    func testWhenUnknownMethodIsRequestedThenNilIsReturned() {
        let subfeature = TrackerProtectionSubfeature()
        XCTAssertNil(subfeature.handler(forMethodNamed: "unknownMethod"))
        XCTAssertNil(subfeature.handler(forMethodNamed: ""))
    }

    // MARK: - ResourceObservation Decoding

    func testWhenResourceObservedParamsAreValidThenDecodesCorrectly() throws {
        let params: [String: Any] = [
            "url": "https://tracker.example/pixel.js",
            "resourceType": "script",
            "potentiallyBlocked": true,
            "pageUrl": "https://example.com"
        ]

        let data = try JSONSerialization.data(withJSONObject: params)
        let observation = try JSONDecoder().decode(TrackerProtectionSubfeature.ResourceObservation.self, from: data)

        XCTAssertEqual(observation.url, "https://tracker.example/pixel.js")
        XCTAssertEqual(observation.resourceType, "script")
        XCTAssertTrue(observation.potentiallyBlocked)
        XCTAssertEqual(observation.pageUrl, "https://example.com")
    }

    func testWhenResourceObservedMissingFieldsThenDecodeFails() {
        let missingUrl: [String: Any] = ["resourceType": "script", "potentiallyBlocked": true, "pageUrl": "https://example.com"]
        let missingType: [String: Any] = ["url": "https://t.example/p.js", "potentiallyBlocked": true, "pageUrl": "https://example.com"]
        let missingBlocked: [String: Any] = ["url": "https://t.example/p.js", "resourceType": "script", "pageUrl": "https://example.com"]
        let missingPage: [String: Any] = ["url": "https://t.example/p.js", "resourceType": "script", "potentiallyBlocked": true]

        for (label, params) in [("url", missingUrl), ("resourceType", missingType),
                                  ("potentiallyBlocked", missingBlocked), ("pageUrl", missingPage)] {
            guard let data = try? JSONSerialization.data(withJSONObject: params) else {
                XCTFail("Failed to serialize params for missing \(label)")
                continue
            }
            XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.ResourceObservation.self, from: data),
                                 "Expected decode failure when \(label) is missing")
        }
    }

    // MARK: - SurrogateInjection Decoding (new minimal schema)

    func testWhenSurrogateInjectedNewSchemaParamsAreValidThenDecodesCorrectly() throws {
        let params: [String: Any] = [
            "url": "https://tracker.example/analytics.js",
            "pageUrl": "https://example.com",
            "surrogateName": "google-analytics.com/analytics.js"
        ]

        let data = try JSONSerialization.data(withJSONObject: params)
        let injection = try JSONDecoder().decode(TrackerProtectionSubfeature.SurrogateInjection.self, from: data)

        XCTAssertEqual(injection.url, "https://tracker.example/analytics.js")
        XCTAssertEqual(injection.pageUrl, "https://example.com")
        XCTAssertEqual(injection.surrogateName, "google-analytics.com/analytics.js")
    }

    // MARK: - SurrogateInjection Decoding (legacy schema migration)

    func testWhenSurrogateInjectedLegacySchemaIsSentThenDecodesWithMigration() throws {
        let params: [String: Any] = [
            "url": "https://tracker.example/analytics.js",
            "blocked": true,
            "reason": "matched rule - surrogate",
            "isSurrogate": true,
            "pageUrl": "https://example.com",
            "entityName": "Tracker Inc",
            "ownerName": "Tracker Inc"
        ]

        let data = try JSONSerialization.data(withJSONObject: params)
        let injection = try JSONDecoder().decode(TrackerProtectionSubfeature.SurrogateInjection.self, from: data)

        XCTAssertEqual(injection.url, "https://tracker.example/analytics.js")
        XCTAssertEqual(injection.pageUrl, "https://example.com")
        XCTAssertNil(injection.surrogateName)
    }

    // MARK: - Message Origin Policy

    func testWhenMessageOriginPolicyIsAccessedThenAllOriginsAreAllowed() {
        let subfeature = TrackerProtectionSubfeature()
        if case .all = subfeature.messageOriginPolicy {
            // expected
        } else {
            XCTFail("Expected .all message origin policy for cross-origin iframe support")
        }
    }

    // MARK: - Malformed Payload Rejection

    func testWhenPayloadIsEmptyThenDecodeFails() {
        let emptyParams: [String: Any] = [:]
        guard let data = try? JSONSerialization.data(withJSONObject: emptyParams) else {
            XCTFail("Failed to serialize empty params")
            return
        }
        XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.ResourceObservation.self, from: data))
        XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.SurrogateInjection.self, from: data))
    }

    func testWhenPayloadHasWrongTypeThenDecodeFails() {
        let wrongTypes: [String: Any] = [
            "url": 123,
            "resourceType": true,
            "potentiallyBlocked": "yes",
            "pageUrl": 456
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: wrongTypes) else {
            XCTFail("Failed to serialize wrong-type params")
            return
        }
        XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.ResourceObservation.self, from: data))
    }

}
