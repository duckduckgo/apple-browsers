//
//  TrackerStatsSubfeatureTests.swift
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
import WebKit
@testable import BrowserServicesKit

final class TrackerStatsSubfeatureTests: XCTestCase {

    var subfeature: TrackerStatsSubfeature!
    var mockDelegate: MockTrackerStatsDelegate!

    @MainActor
    override func setUp() {
        super.setUp()
        mockDelegate = MockTrackerStatsDelegate()
        subfeature = TrackerStatsSubfeature(delegate: mockDelegate)
    }

    @MainActor
    override func tearDown() {
        subfeature = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Handler Registration

    func testHandlerForSurrogateInjected() {
        let handler = subfeature.handler(forMethodNamed: "surrogateInjected")
        XCTAssertNotNil(handler, "Should have handler for surrogateInjected")
    }

    func testHandlerForIsCTLEnabled() {
        let handler = subfeature.handler(forMethodNamed: "isCTLEnabled")
        XCTAssertNotNil(handler, "Should have handler for isCTLEnabled")
    }

    func testHandlerForTrackerDetected() {
        let handler = subfeature.handler(forMethodNamed: "trackerDetected")
        XCTAssertNotNil(handler, "Should have handler for trackerDetected")
    }

    func testHandlerForUnknownMethod() {
        let handler = subfeature.handler(forMethodNamed: "unknownMethod")
        XCTAssertNil(handler, "Should not have handler for unknown method")
    }

    // MARK: - CTL Enabled Check

    @MainActor
    func testIsCTLEnabledReturnsTrue() async throws {
        mockDelegate.ctlEnabled = true

        let handler = subfeature.handler(forMethodNamed: "isCTLEnabled")!
        let result = try await handler([:], TrackerStatsMockWKScriptMessage())

        XCTAssertEqual(result as? Bool, true)
    }

    @MainActor
    func testIsCTLEnabledReturnsFalse() async throws {
        mockDelegate.ctlEnabled = false

        let handler = subfeature.handler(forMethodNamed: "isCTLEnabled")!
        let result = try await handler([:], TrackerStatsMockWKScriptMessage())

        XCTAssertEqual(result as? Bool, false)
    }

    @MainActor
    func testIsCTLEnabledDefaultsToFalseWithNoDelegate() async throws {
        subfeature = TrackerStatsSubfeature(delegate: nil)

        let handler = subfeature.handler(forMethodNamed: "isCTLEnabled")!
        let result = try await handler([:], TrackerStatsMockWKScriptMessage())

        XCTAssertEqual(result as? Bool, false)
    }

    // MARK: - Feature Name

    func testFeatureName() {
        XCTAssertEqual(subfeature.featureName, "trackerStats")
    }
}

// MARK: - Mocks

@MainActor
final class MockTrackerStatsDelegate: TrackerStatsSubfeatureDelegate {

    var shouldProcessTrackers = true
    var ctlEnabled = false
    var surrogateInjections: [TrackerStatsSubfeature.SurrogateInjection] = []
    var trackerDetections: [TrackerStatsSubfeature.TrackerDetection] = []

    func trackerStats(_ subfeature: TrackerStatsSubfeature,
                      didDetectTracker tracker: TrackerStatsSubfeature.TrackerDetection) {
        trackerDetections.append(tracker)
    }

    func trackerStats(_ subfeature: TrackerStatsSubfeature,
                      didInjectSurrogate surrogate: TrackerStatsSubfeature.SurrogateInjection) {
        surrogateInjections.append(surrogate)
    }

    func trackerStatsShouldEnableCTL(_ subfeature: TrackerStatsSubfeature) -> Bool {
        return ctlEnabled
    }

    func trackerStatsShouldProcessTrackers(_ subfeature: TrackerStatsSubfeature) -> Bool {
        return shouldProcessTrackers
    }
}

final class TrackerStatsMockWKScriptMessage: WKScriptMessage {
    override var body: Any { return [:] }
    override var name: String { return "test" }
}
