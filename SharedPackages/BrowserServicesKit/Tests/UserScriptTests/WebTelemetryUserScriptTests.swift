//
//  WebTelemetryUserScriptTests.swift
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

import Foundation
import WebKit
import XCTest

@testable import UserScript

final class WebTelemetryUserScriptTests: XCTestCase {

    // MARK: - Handler Registration Tests

    func testHandlerReturnsFunctionForVideoPlaybackMethod() {
        let script = WebTelemetryUserScript()
        let handler = script.handler(forMethodNamed: "video-playback")

        XCTAssertNotNil(handler, "Should return a handler for video-playback method")
    }

    func testHandlerReturnsNilForUnknownMethod() {
        let script = WebTelemetryUserScript()
        let handler = script.handler(forMethodNamed: "unknownMethod")

        XCTAssertNil(handler, "Should return nil for unknown method names")
    }

    func testHandlerReturnsNilForEmptyMethodName() {
        let script = WebTelemetryUserScript()
        let handler = script.handler(forMethodNamed: "")

        XCTAssertNil(handler, "Should return nil for empty method name")
    }

    // MARK: - Data Model Tests

    func testVideoPlaybackPayloadCodable() throws {
        let payload = WebTelemetryUserScript.VideoPlaybackPayload(userInteraction: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WebTelemetryUserScript.VideoPlaybackPayload.self, from: data)

        XCTAssertEqual(payload, decoded, "Should round-trip through JSON encoding/decoding")
    }

    func testVideoPlaybackPayloadDecodesFromJS() throws {
        let json = #"{"userInteraction": false}"#
        let data = json.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WebTelemetryUserScript.VideoPlaybackPayload.self, from: data)

        XCTAssertFalse(decoded.userInteraction)
    }

    // MARK: - Subfeature Configuration Tests

    func testFeatureNameIsWebTelemetry() {
        let script = WebTelemetryUserScript()

        XCTAssertEqual(script.featureName, "webTelemetry", "Feature name should be 'webTelemetry'")
    }

    func testMessageOriginPolicyIsAll() {
        let script = WebTelemetryUserScript()

        if case .all = script.messageOriginPolicy {
            // Pass
        } else {
            XCTFail("Message origin policy should be .all")
        }
    }

    // MARK: - Delegate Tests

    func testDelegateIsWeaklyReferenced() {
        let script = WebTelemetryUserScript()
        var delegate: MockWebTelemetryUserScriptDelegate? = MockWebTelemetryUserScriptDelegate()

        script.delegate = delegate
        XCTAssertNotNil(script.delegate, "Delegate should be set")

        delegate = nil
        XCTAssertNil(script.delegate, "Delegate should be nil after deallocation (weak reference)")
    }

    func testBrokerIsWeaklyReferenced() {
        let script = WebTelemetryUserScript()
        var broker: UserScriptMessageBroker? = UserScriptMessageBroker(context: "test")

        script.broker = broker
        XCTAssertNotNil(script.broker, "Broker should be set")

        broker = nil
        XCTAssertNil(script.broker, "Broker should be nil after deallocation (weak reference)")
    }
}

// MARK: - Mocks

private final class MockWebTelemetryUserScriptDelegate: WebTelemetryUserScriptDelegate {
    var receivedUserInteraction: Bool?

    @MainActor
    func webTelemetryUserScript(_ webTelemetryUserScript: WebTelemetryUserScript,
                                didDetectVideoPlayback payload: WebTelemetryUserScript.VideoPlaybackPayload,
                                in webView: WKWebView?) {
        receivedUserInteraction = payload.userInteraction
    }
}
