//
//  EventHubImmediatePixelTests.swift
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
@testable import EventHub

@Suite("EventHub immediate pixels")
struct EventHubImmediatePixelTests {
    static let immediateConfig = """
    { "telemetry": { "webEvent_impression": {
        "state": "enabled",
        "trigger": { "type": "immediate", "source": "impression" },
        "parameters": {}
    } } }
    """

    @Test("immediate trigger fires one pixel per event")
    func immediateTriggerFiresOnePixelPerEvent() {
        let f = EventHubFixture.active(Self.immediateConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("impression"), tabID: .new())
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.name == "webEvent_impression")
    }

    @Test("immediate pixels are not deduplicated")
    func immediatePixelsAreNotDeduplicated() {
        let f = EventHubFixture.active(Self.immediateConfig)
        let tab = EventHubTabID.new()
        f.manager.handleWebEvent(EventHubFixture.webEvent("impression"), tabID: tab)
        f.manager.handleWebEvent(EventHubFixture.webEvent("impression"), tabID: tab)
        f.manager.handleWebEvent(EventHubFixture.webEvent("impression"), tabID: tab)
        #expect(f.fired.count == 3)
    }

    @Test("immediate pixels fire without the app being foregrounded")
    func immediatePixelsFireWithoutForeground() {
        // No onAppForegrounded — immediate pixels are not foreground-gated.
        let f = EventHubFixture.background(Self.immediateConfig)
        f.manager.onConfigChanged()
        f.manager.handleWebEvent(EventHubFixture.webEvent("impression"), tabID: .new())
        #expect(f.fired.count == 1)
    }

    @Test("immediate pixels do not persist state")
    func immediatePixelsDoNotPersistState() {
        let f = EventHubFixture.active(Self.immediateConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("impression"), tabID: .new())
        #expect(f.repository.allPixelStates().isEmpty)
    }

    @Test("immediate ignores an unknown event type")
    func immediateIgnoresUnknownEventType() {
        let f = EventHubFixture.active(Self.immediateConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("something-else"), tabID: .new())
        #expect(f.fired.isEmpty)
    }

    @Test("immediate does not fire when the feature is disabled")
    func immediateDoesNotFireWhenDisabled() {
        let f = EventHubFixture.active(Self.immediateConfig, enabled: false)
        f.manager.handleWebEvent(EventHubFixture.webEvent("impression"), tabID: .new())
        #expect(f.fired.isEmpty)
    }
}
