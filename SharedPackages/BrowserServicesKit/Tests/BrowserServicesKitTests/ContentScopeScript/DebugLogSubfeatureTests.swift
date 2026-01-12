//
//  DebugLogSubfeatureTests.swift
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

final class DebugLogSubfeatureTests: XCTestCase {

    var subfeature: DebugLogSubfeature!
    var mockInstrumentation: MockDebugLogInstrumentation!

    override func setUp() {
        super.setUp()
        mockInstrumentation = MockDebugLogInstrumentation()
        subfeature = DebugLogSubfeature(instrumentation: mockInstrumentation)
    }

    override func tearDown() {
        subfeature = nil
        mockInstrumentation = nil
        super.tearDown()
    }

    // MARK: - Handler Registration

    func testHandlerForDebugLog() {
        let handler = subfeature.handler(forMethodNamed: "debugLog")
        XCTAssertNotNil(handler, "Should have handler for debugLog")
    }

    func testHandlerForSignpost() {
        let handler = subfeature.handler(forMethodNamed: "signpost")
        XCTAssertNotNil(handler, "Should have handler for signpost")
    }

    func testHandlerForUnknownMethod() {
        let handler = subfeature.handler(forMethodNamed: "unknownMethod")
        XCTAssertNil(handler, "Should not have handler for unknown method")
    }

    // MARK: - Debug Log

    func testDebugLogHandlesValidMessage() async throws {
        let params: [String: Any] = [
            "level": "info",
            "feature": "trackerStats",
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "args": ["Test message", "with", "multiple args"]
        ]

        let handler = subfeature.handler(forMethodNamed: "debugLog")!

        // Should not throw - in DEBUG builds this logs, in release it's a no-op
        _ = try await handler(params, MockDebugLogWKScriptMessage())
    }

    func testDebugLogHandlesEmptyArgs() async throws {
        let params: [String: Any] = [
            "level": "info",
            "feature": "trackerStats",
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "args": [] as [String]
        ]

        let handler = subfeature.handler(forMethodNamed: "debugLog")!
        _ = try await handler(params, MockDebugLogWKScriptMessage())
    }

    // MARK: - Signpost - Request Allowed

    func testSignpostRequestAllowed() async throws {
        let params: [String: Any] = [
            "event": "Request Allowed",
            "url": "https://example.com/resource.js",
            "time": 5.0
        ]

        let handler = subfeature.handler(forMethodNamed: "signpost")!
        _ = try await handler(params, MockDebugLogWKScriptMessage())

        XCTAssertEqual(mockInstrumentation.requestAllowedCalls.count, 1)
        XCTAssertEqual(mockInstrumentation.requestAllowedCalls.first?.url, "https://example.com/resource.js")
        XCTAssertEqual(mockInstrumentation.requestAllowedCalls.first?.time, 5.0)
    }

    // MARK: - Signpost - Tracker Allowed

    func testSignpostTrackerAllowed() async throws {
        let params: [String: Any] = [
            "event": "Tracker Allowed",
            "url": "https://tracker.com/pixel.gif",
            "time": 3.0,
            "reason": "first party"
        ]

        let handler = subfeature.handler(forMethodNamed: "signpost")!
        _ = try await handler(params, MockDebugLogWKScriptMessage())

        XCTAssertEqual(mockInstrumentation.trackerAllowedCalls.count, 1)
        XCTAssertEqual(mockInstrumentation.trackerAllowedCalls.first?.url, "https://tracker.com/pixel.gif")
        XCTAssertEqual(mockInstrumentation.trackerAllowedCalls.first?.time, 3.0)
        XCTAssertEqual(mockInstrumentation.trackerAllowedCalls.first?.reason, "first party")
    }

    // MARK: - Signpost - Tracker Blocked

    func testSignpostTrackerBlocked() async throws {
        let params: [String: Any] = [
            "event": "Tracker Blocked",
            "url": "https://tracker.com/pixel.gif",
            "time": 2.5
        ]

        let handler = subfeature.handler(forMethodNamed: "signpost")!
        _ = try await handler(params, MockDebugLogWKScriptMessage())

        XCTAssertEqual(mockInstrumentation.trackerBlockedCalls.count, 1)
        XCTAssertEqual(mockInstrumentation.trackerBlockedCalls.first?.url, "https://tracker.com/pixel.gif")
        XCTAssertEqual(mockInstrumentation.trackerBlockedCalls.first?.time, 2.5)
    }

    // MARK: - Signpost - Surrogate Injected

    func testSignpostSurrogateInjected() async throws {
        let params: [String: Any] = [
            "event": "Surrogate Injected",
            "url": "https://tracker.com/sdk.js",
            "time": 1.0
        ]

        let handler = subfeature.handler(forMethodNamed: "signpost")!
        _ = try await handler(params, MockDebugLogWKScriptMessage())

        XCTAssertEqual(mockInstrumentation.jsEventCalls.count, 1)
        XCTAssertEqual(mockInstrumentation.jsEventCalls.first?.name, "surrogate:https://tracker.com/sdk.js")
        XCTAssertEqual(mockInstrumentation.jsEventCalls.first?.time, 1.0)
    }

    // MARK: - Signpost - Generic

    func testSignpostGeneric() async throws {
        let params: [String: Any] = [
            "event": "Generic",
            "name": "pageLoad",
            "time": 100.0
        ]

        let handler = subfeature.handler(forMethodNamed: "signpost")!
        _ = try await handler(params, MockDebugLogWKScriptMessage())

        XCTAssertEqual(mockInstrumentation.jsEventCalls.count, 1)
        XCTAssertEqual(mockInstrumentation.jsEventCalls.first?.name, "pageLoad")
        XCTAssertEqual(mockInstrumentation.jsEventCalls.first?.time, 100.0)
    }

    // MARK: - No Instrumentation

    func testSignpostWithNoInstrumentation() async throws {
        subfeature = DebugLogSubfeature(instrumentation: nil)

        let params: [String: Any] = [
            "event": "Request Allowed",
            "url": "https://example.com/resource.js",
            "time": 5.0
        ]

        let handler = subfeature.handler(forMethodNamed: "signpost")!
        // Should not crash when instrumentation is nil
        _ = try await handler(params, MockDebugLogWKScriptMessage())
    }

    // MARK: - Feature Name

    func testFeatureName() {
        XCTAssertEqual(subfeature.featureName, "debug")
    }
}

// MARK: - Mocks

final class MockDebugLogInstrumentation: DebugLogInstrumentation {

    struct RequestAllowedCall {
        let url: String
        let time: Double
    }

    struct TrackerAllowedCall {
        let url: String
        let time: Double
        let reason: String?
    }

    struct TrackerBlockedCall {
        let url: String
        let time: Double
    }

    struct JSEventCall {
        let name: String
        let time: Double
    }

    var requestAllowedCalls: [RequestAllowedCall] = []
    var trackerAllowedCalls: [TrackerAllowedCall] = []
    var trackerBlockedCalls: [TrackerBlockedCall] = []
    var jsEventCalls: [JSEventCall] = []

    func request(url: String, allowedIn timeInMs: Double) {
        requestAllowedCalls.append(RequestAllowedCall(url: url, time: timeInMs))
    }

    func tracker(url: String, allowedIn timeInMs: Double, reason: String?) {
        trackerAllowedCalls.append(TrackerAllowedCall(url: url, time: timeInMs, reason: reason))
    }

    func tracker(url: String, blockedIn timeInMs: Double) {
        trackerBlockedCalls.append(TrackerBlockedCall(url: url, time: timeInMs))
    }

    func jsEvent(name: String, executedIn timeInMs: Double) {
        jsEventCalls.append(JSEventCall(name: name, time: timeInMs))
    }
}

final class MockDebugLogWKScriptMessage: WKScriptMessage {
    override var body: Any { return [:] }
    override var name: String { return "test" }
}
