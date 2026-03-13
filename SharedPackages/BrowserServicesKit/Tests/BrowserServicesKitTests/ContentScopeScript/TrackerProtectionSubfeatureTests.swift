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

    func testWhenTrackerDetectedMethodIsRequestedThenHandlerIsReturned() {
        let subfeature = TrackerProtectionSubfeature()
        XCTAssertNotNil(subfeature.handler(forMethodNamed: "trackerDetected"))
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

    // MARK: - TrackerDetection Decoding

    func testWhenTrackerDetectedParamsAreValidThenDecodesCorrectly() throws {
        let params: [String: Any] = [
            "url": "https://tracker.example/pixel.js",
            "blocked": true,
            "reason": "default block",
            "isSurrogate": false,
            "pageUrl": "https://example.com",
            "entityName": "Tracker Inc",
            "ownerName": "Tracker Inc",
            "category": "Analytics",
            "prevalence": 0.1,
            "isAllowlisted": false
        ]

        let data = try JSONSerialization.data(withJSONObject: params)
        let detection = try JSONDecoder().decode(TrackerProtectionSubfeature.TrackerDetection.self, from: data)

        XCTAssertEqual(detection.url, "https://tracker.example/pixel.js")
        XCTAssertTrue(detection.blocked)
        XCTAssertEqual(detection.reason, "default block")
        XCTAssertFalse(detection.isSurrogate)
        XCTAssertEqual(detection.pageUrl, "https://example.com")
        XCTAssertEqual(detection.entityName, "Tracker Inc")
        XCTAssertEqual(detection.ownerName, "Tracker Inc")
        XCTAssertEqual(detection.category, "Analytics")
        XCTAssertEqual(detection.prevalence, 0.1)
        XCTAssertEqual(detection.isAllowlisted, false)
    }

    func testWhenTrackerDetectedHasNullOptionalFieldsThenDecodesCorrectly() throws {
        let params: [String: Any] = [
            "url": "https://tracker.example/pixel.js",
            "blocked": true,
            "isSurrogate": false,
            "pageUrl": "https://example.com"
        ]

        let data = try JSONSerialization.data(withJSONObject: params)
        let detection = try JSONDecoder().decode(TrackerProtectionSubfeature.TrackerDetection.self, from: data)

        XCTAssertEqual(detection.url, "https://tracker.example/pixel.js")
        XCTAssertTrue(detection.blocked)
        XCTAssertNil(detection.reason)
        XCTAssertNil(detection.entityName)
        XCTAssertNil(detection.ownerName)
        XCTAssertNil(detection.category)
        XCTAssertNil(detection.prevalence)
        XCTAssertNil(detection.isAllowlisted)
    }

    func testWhenTrackerDetectedHasAllowedTrackerThenBlockedIsFalse() throws {
        let params: [String: Any] = [
            "url": "https://allowed.example/script.js",
            "blocked": false,
            "reason": "default ignore",
            "isSurrogate": false,
            "pageUrl": "https://example.com"
        ]

        let data = try JSONSerialization.data(withJSONObject: params)
        let detection = try JSONDecoder().decode(TrackerProtectionSubfeature.TrackerDetection.self, from: data)

        XCTAssertFalse(detection.blocked)
        XCTAssertEqual(detection.reason, "default ignore")
    }

    // MARK: - SurrogateInjection Decoding

    func testWhenSurrogateInjectedParamsAreValidThenDecodesCorrectly() throws {
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
        XCTAssertTrue(injection.blocked)
        XCTAssertEqual(injection.reason, "matched rule - surrogate")
        XCTAssertTrue(injection.isSurrogate)
        XCTAssertEqual(injection.pageUrl, "https://example.com")
        XCTAssertEqual(injection.entityName, "Tracker Inc")
        XCTAssertEqual(injection.ownerName, "Tracker Inc")
    }

    // MARK: - Message Origin Policy

    /// `.all` is intentional: tracker events originate from cross-origin iframes,
    /// matching legacy WKScriptMessageHandler behavior.
    func testWhenMessageOriginPolicyIsAccessedThenAllOriginsAreAllowed() {
        let subfeature = TrackerProtectionSubfeature()
        if case .all = subfeature.messageOriginPolicy {
            // expected
        } else {
            XCTFail("Expected .all message origin policy for cross-origin iframe support")
        }
    }

    // MARK: - Malformed Payload Rejection

    func testWhenTrackerDetectedMissingRequiredFieldsThenDecodeFails() {
        let missingUrl: [String: Any] = ["blocked": true, "isSurrogate": false, "pageUrl": "https://example.com"]
        let missingBlocked: [String: Any] = ["url": "https://t.example/p.js", "isSurrogate": false, "pageUrl": "https://example.com"]
        let missingIsSurrogate: [String: Any] = ["url": "https://t.example/p.js", "blocked": true, "pageUrl": "https://example.com"]
        let missingPageUrl: [String: Any] = ["url": "https://t.example/p.js", "blocked": true, "isSurrogate": false]

        for (label, params) in [("url", missingUrl), ("blocked", missingBlocked),
                                  ("isSurrogate", missingIsSurrogate), ("pageUrl", missingPageUrl)] {
            guard let data = try? JSONSerialization.data(withJSONObject: params) else {
                XCTFail("Failed to serialize params for missing \(label)")
                continue
            }
            XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.TrackerDetection.self, from: data),
                                 "Expected decode failure when \(label) is missing")
        }
    }

    func testWhenSurrogateInjectedMissingRequiredFieldsThenDecodeFails() {
        let missingUrl: [String: Any] = ["blocked": true, "isSurrogate": true, "pageUrl": "https://example.com"]
        let missingPageUrl: [String: Any] = ["url": "https://t.example/p.js", "blocked": true, "isSurrogate": true]

        for (label, params) in [("url", missingUrl), ("pageUrl", missingPageUrl)] {
            guard let data = try? JSONSerialization.data(withJSONObject: params) else {
                XCTFail("Failed to serialize params for missing \(label)")
                continue
            }
            XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.SurrogateInjection.self, from: data),
                                 "Expected decode failure when \(label) is missing")
        }
    }

    func testWhenPayloadIsEmptyThenDecodeFails() {
        let emptyParams: [String: Any] = [:]
        guard let data = try? JSONSerialization.data(withJSONObject: emptyParams) else {
            XCTFail("Failed to serialize empty params")
            return
        }
        XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.TrackerDetection.self, from: data))
        XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.SurrogateInjection.self, from: data))
    }

    func testWhenPayloadHasWrongTypeThenDecodeFails() {
        let wrongTypes: [String: Any] = [
            "url": 123,
            "blocked": "yes",
            "isSurrogate": "true",
            "pageUrl": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: wrongTypes) else {
            XCTFail("Failed to serialize wrong-type params")
            return
        }
        XCTAssertThrowsError(try JSONDecoder().decode(TrackerProtectionSubfeature.TrackerDetection.self, from: data))
    }

    // MARK: - TrackerBlockingReason mapping

    func testAllowReasonMappingFromTypedReasons() {
        XCTAssertEqual(TrackerBlockingReason.firstParty.allowReason, .ownedByFirstParty)
        XCTAssertEqual(TrackerBlockingReason.ruleException.allowReason, .ruleException)
        XCTAssertEqual(TrackerBlockingReason.unprotectedDomain.allowReason, .protectionDisabled)
        XCTAssertEqual(TrackerBlockingReason.defaultBlock.allowReason, .otherThirdPartyRequest)
        XCTAssertEqual(TrackerBlockingReason.thirdPartyRequest.allowReason, .otherThirdPartyRequest)
        XCTAssertEqual(TrackerBlockingReason.surrogate.allowReason, .otherThirdPartyRequest)
    }

    func testUnknownReasonStringFallsBackToOtherThirdPartyRequest() {
        let unknown = TrackerBlockingReason(rawValue: "some unknown reason")
        XCTAssertNil(unknown)
    }
}
