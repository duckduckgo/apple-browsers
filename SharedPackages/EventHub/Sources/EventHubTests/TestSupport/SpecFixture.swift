//
//  SpecFixture.swift
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
@testable import EventHub

/// Harness for the cross-platform behavioural specifications in `docs/event-hub/tests/`
/// (`duckduckgo/ddg-workflow`). Wraps `EventHubFixture` in the vocabulary those documents use —
/// pages, events, payloads, period end — so a spec case reads as the document writes it.
final class SpecFixture {
    private let fixture: EventHubFixture
    private let periodSeconds: TimeInterval

    init(_ settingsJSON: String, periodSeconds: TimeInterval = 86400) {
        self.fixture = EventHubFixture.active(settingsJSON)
        self.periodSeconds = periodSeconds
    }

    var manager: EventHub { fixture.manager }

    // MARK: Pages

    /// Opens `url` in a new tab and returns it.
    ///
    /// Every case starts a page this way, and that matters: the hub's tab→URL map begins empty, so a
    /// tab's *first* navigation records the URL without clearing anything. That is right in
    /// production, where a page loads before any content script can fire, but it means an event sent
    /// before a tab's first navigation would be wrongly treated as a repeat by the navigation that
    /// follows it. Opening the page first models the real sequence.
    func openPage(url: String = "https://example.com/page") -> EventHubTabID {
        let tab = EventHubTabID.new()
        navigate(tab, to: url)
        return tab
    }

    func navigate(_ tab: EventHubTabID, to url: String) {
        fixture.manager.onNavigationStarted(tabID: tab, url: url)
    }

    // MARK: Events

    /// A web event carrying a single `reason` payload member — the shape most cases use.
    func send(_ type: String, reason: String, on tab: EventHubTabID) {
        sendRaw(type, dataJSON: #"{ "reason": "\#(reason)" }"#, on: tab)
    }

    /// A web event whose payload is written out as JSON, for cases that care about its exact shape.
    func sendRaw(_ type: String, dataJSON: String, on tab: EventHubTabID) {
        fixture.manager.handleWebEvent(EventHubFixture.eventWithData(type, dataJSON: dataJSON), tabID: tab)
    }

    /// A web event with the `data` member absent altogether, as distinct from present and empty.
    func sendWithoutData(_ type: String, on tab: EventHubTabID) {
        fixture.manager.handleWebEvent(EventHubFixture.webEvent(type), tabID: tab)
    }

    /// A browser-native event: no tab, no URL, and so never de-duplicated.
    func sendNative(_ type: String, payload: [String: String]) {
        fixture.manager.handleImmediateEvent(type, data: payload)
    }

    // MARK: Observation

    /// Ends each running period once, per the suites' model: events are delivered, then the current
    /// period ends.
    func endPeriod() {
        fixture.advance(by: periodSeconds)
    }

    /// Every pixel fired, written as the specifications write them — `name?param=value`, sorted so a
    /// case can state its complete expected set and an over-fire fails as loudly as a missing pixel.
    ///
    /// Data values are percent-decoded back to the compact JSON the cases quote (`reason="overlay"`
    /// rather than `reason=%22overlay%22`); the encoding itself is pinned separately, by
    /// `EventHubDataParameterTests`. The time-derived `attributionPeriod` is excluded, as the suites
    /// specify.
    var fired: [String] {
        fixture.fired.map { pixel in
            let parameters = pixel.parameters
                .filter { $0.key != "attributionPeriod" }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.removingPercentEncoding ?? $0.value)" }
                .joined(separator: "&")
            return parameters.isEmpty ? pixel.name : "\(pixel.name)?\(parameters)"
        }
        .sorted()
    }
}
