//
//  ContentScopePropertiesTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import WebKit
@testable import BrowserServicesKit
import TrackerRadarKit

class ContentScopePropertiesTests: XCTestCase {
    func testContentScopePropertiesInitializeCorrectly() {
        let properties = ContentScopeProperties(gpcEnabled: true, sessionKey: "123456", messageSecret: "123456", featureToggles: ContentScopeFeatureToggles.allTogglesOn)

        // ensure the properties can be encoded to valid JSON
        XCTAssertNotNil(try? JSONEncoder().encode(properties))

        // ensure the platform.name key exists, as this will be expected in the output JSON
        XCTAssertEqual(properties.platform.name, ContentScopePlatform().name)
    }

    func testTrackerDataEncodedIntoUserPreferences() {
        let trackerData = TrackerData(
            trackers: ["tracker.example": KnownTracker(
                domain: "tracker.example",
                defaultAction: .block,
                owner: KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc", ownedBy: nil),
                prevalence: 0.1,
                subdomains: nil,
                categories: nil,
                rules: nil
            )],
            entities: ["Tracker Inc": Entity(displayName: "Tracker Inc", domains: ["tracker.example"], prevalence: 0.1)],
            domains: ["tracker.example": "Tracker Inc"],
            cnames: nil
        )

        let properties = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: "test-session",
            messageSecret: "test-secret",
            featureToggles: ContentScopeFeatureToggles.allTogglesOn,
            trackerData: trackerData
        )

        // Encode to JSON
        guard let jsonData = try? JSONEncoder().encode(properties),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to encode ContentScopeProperties")
            return
        }

        // Verify trackerData is present and contains expected structure
        guard let encodedTrackerData = json["trackerData"] as? [String: Any] else {
            XCTFail("trackerData missing from encoded properties")
            return
        }

        XCTAssertNotNil(encodedTrackerData["trackers"], "trackerData should contain trackers")
        XCTAssertNotNil(encodedTrackerData["entities"], "trackerData should contain entities")
        XCTAssertNotNil(encodedTrackerData["domains"], "trackerData should contain domains")

        // Verify the tracker domain is present
        guard let trackers = encodedTrackerData["trackers"] as? [String: Any] else {
            XCTFail("trackers should be a dictionary")
            return
        }
        XCTAssertNotNil(trackers["tracker.example"], "tracker.example should be in trackers")
    }

    func testTrackerDataNilByDefault() {
        let properties = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: "test-session",
            messageSecret: "test-secret",
            featureToggles: ContentScopeFeatureToggles.allTogglesOn
        )

        XCTAssertNil(properties.trackerData, "trackerData should be nil by default")

        // Verify the properties still encode correctly even with nil trackerData
        guard let jsonData = try? JSONEncoder().encode(properties),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to encode ContentScopeProperties")
            return
        }

        // When trackerData is nil, Swift's Encodable omits the key entirely.
        // This is fine - C-S-S handles absence of the key gracefully.
        XCTAssertFalse(json.keys.contains("trackerData"), "trackerData key should be omitted when nil")
    }
}
