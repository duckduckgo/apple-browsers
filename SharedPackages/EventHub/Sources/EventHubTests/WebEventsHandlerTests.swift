//
//  WebEventsHandlerTests.swift
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

import Testing
import Foundation
import WebKit
@testable import EventHub

@Suite("WebEventsHandler")
struct WebEventsHandlerTests {
    private final class SpyManager: EventHubManaging {
        var handledWebEvents: [(data: [String: Any], tabID: EventHubTabID)] = []
        func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID) {
            handledWebEvents.append((webEventData, tabID))
        }
        func handleImmediateEvent(_ type: String, data: Encodable?) {}
        func handleAggregatedEvent(_ type: String, data: Encodable?) {}
        func onNavigationStarted(tabID: EventHubTabID, url: String) {}
        func onTabClosed(tabID: EventHubTabID) {}
        func onConfigChanged() {}
        func isEnabled() -> Bool { true }
        func onAppForegrounded() {}
        func onAppBackgrounded() {}
    }

    @Test("featureName targets webEvents")
    func featureNameTargetsWebEvents() {
        let handler = WebEventsHandler(manager: SpyManager(), tabIDProvider: { _ in .new() })
        #expect(handler.featureName == "webEvents")
    }

    @Test("handler forwards an event with a type to the manager")
    func handlerForwardsEventWithTypeToManager() async throws {
        let manager = SpyManager()
        let tab = EventHubTabID.new()
        let handler = WebEventsHandler(manager: manager, tabIDProvider: { _ in tab })

        let notify = try #require(handler.handler(forMethodNamed: "webEvent"))
        await bootstrapWebKitForTesting()
        _ = try await notify(["type": "click", "data": [String: Any]()], WKScriptMessage())

        #expect(manager.handledWebEvents.count == 1)
        #expect(manager.handledWebEvents.first?.data["type"] as? String == "click")
        #expect(manager.handledWebEvents.first?.tabID == tab)
    }

    @Test("handler does not forward when type is missing or empty", arguments: [
        ["data": [String: Any]()],
        ["type": "", "data": [String: Any]()],
    ] as [[String: Any]])
    func handlerDoesNotForwardWhenTypeMissingOrEmpty(params: [String: Any]) async throws {
        let manager = SpyManager()
        let handler = WebEventsHandler(manager: manager, tabIDProvider: { _ in .new() })

        let notify = try #require(handler.handler(forMethodNamed: "webEvent"))
        await bootstrapWebKitForTesting()
        _ = try await notify(params, WKScriptMessage())

        #expect(manager.handledWebEvents.isEmpty)
    }
}
