//
//  SubscriptionEventsTests.swift
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
@testable import WebExtensions

final class WebExtensionEventOutboxTests: XCTestCase {

    func testDrainReturnsEventsInOrderAndEmptiesTheOutbox() {
        let outbox = WebExtensionEventOutbox()
        outbox.enqueue(WebExtensionSubscriptionEvent(featureName: "a", subscriptionName: "x"))
        outbox.enqueue(WebExtensionSubscriptionEvent(featureName: "b", subscriptionName: "x"))

        XCTAssertEqual(outbox.drain().map(\.featureName), ["a", "b"])
        XCTAssertTrue(outbox.drain().isEmpty)
    }

    func testNewerEventReplacesQueuedEventForTheSameSubscription() {
        let outbox = WebExtensionEventOutbox()
        outbox.enqueue(WebExtensionSubscriptionEvent(featureName: "a", subscriptionName: "x", params: ["n": 1]))
        outbox.enqueue(WebExtensionSubscriptionEvent(featureName: "a", subscriptionName: "y"))
        outbox.enqueue(WebExtensionSubscriptionEvent(featureName: "a", subscriptionName: "x", params: ["n": 2]))

        let drained = outbox.drain()
        XCTAssertEqual(drained.map(\.subscriptionName), ["y", "x"], "the replacing event moves to the end")
        XCTAssertEqual(drained.last?.params["n"] as? Int, 2)
    }
}

@available(iOS 18.4, macOS 15.4, *)
final class SubscriptionEventsWebExtensionMessageHandlerTests: XCTestCase {

    private func message(_ method: String) -> WebExtensionMessage {
        WebExtensionMessage(featureName: "nativeEvents", method: method, id: "1", params: [:], context: nil, extensionIdentifier: "test")
    }

    func testDrainEventsReturnsAndClearsQueuedEvents() async {
        let outbox = WebExtensionEventOutbox()
        outbox.enqueue(WebExtensionSubscriptionEvent(featureName: "userAllowlist", subscriptionName: "onAllowlistChanged",
                                                     params: ["version": "v1"]))
        let handler = SubscriptionEventsWebExtensionMessageHandler(outbox: outbox)
        XCTAssertEqual(handler.handledFeatureName, "nativeEvents")

        guard case .success(let payload) = await handler.handleMessage(message("drainEvents")),
              let events = (payload as? [String: Any])?["events"] as? [[String: Any]] else {
            return XCTFail("expected .success with an events array")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["featureName"] as? String, "userAllowlist")
        XCTAssertEqual(events.first?["subscriptionName"] as? String, "onAllowlistChanged")
        XCTAssertEqual((events.first?["params"] as? [String: Any])?["version"] as? String, "v1")
        XCTAssertTrue(outbox.drain().isEmpty)
    }

    func testUnknownMethodFails() async {
        let handler = SubscriptionEventsWebExtensionMessageHandler(outbox: WebExtensionEventOutbox())
        guard case .failure = await handler.handleMessage(message("nope")) else { return XCTFail("expected .failure") }
    }
}
