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
    private let longestPeriodSeconds: TimeInterval

    /// - Parameters:
    ///   - settingsJSON: the `eventHub` feature settings, i.e. the telemetry configuration. `"{}"` for
    ///     the metrics suite, which configures no telemetry at all.
    ///   - experiments: the raw `settings` JSON of each experiment subfeature, keyed by subfeature ID —
    ///     where `metrics` is declared.
    ///   - enrolled: the experiments the framework considers active.
    ///   - longestPeriodSeconds: how far `endPeriod()` advances the clock — the longest period the
    ///     config declares, so that every running period ends.
    init(_ settingsJSON: String, longestPeriodSeconds: TimeInterval = 86400,
         experiments: [String: String] = [:], enrolled: Set<String> = []) {
        self.fixture = EventHubFixture.active(settingsJSON, experimentSettings: experiments, enrolled: enrolled)
        self.longestPeriodSeconds = longestPeriodSeconds
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
        fixture.manager.handleNativeEvent(type, data: payload)
    }

    // MARK: Configuration lifecycle

    /// Enrols the user in `experiments`, replacing any previous enrollment.
    func enroll(in experiments: Set<String>) {
        fixture.setEnrolled(experiments)
    }

    /// Applies a new remote config for the experiment subfeatures, replacing the previous one.
    func setExperiments(_ experiments: [String: String]) {
        fixture.setExperimentSettings(experiments)
    }

    /// Turns the `eventHub` feature itself on or off, as its remote `state` would (M-LIF-6, T-GEN-P1).
    func setFeatureEnabled(_ enabled: Bool) {
        fixture.setEnabled(enabled)
    }

    // MARK: Observation

    /// Ends each running period exactly once, per the suites' model: events are delivered, then each
    /// period pixel's current period ends.
    ///
    /// One clock jump suffices however many period lengths are configured, and however far apart they
    /// are. A rollover starts the replacement period at `now` rather than at the boundary just passed,
    /// so a pixel whose period elapsed during the jump fires once and its new period is then still
    /// running — a 1-day and a 7-day pixel both end once here, and neither ends twice.
    func endPeriod() {
        fixture.advance(by: longestPeriodSeconds)
    }

    /// Every pixel fired, written as the specifications write them — `name?param=value`, sorted so a
    /// case can state its complete expected set and an over-fire fails as loudly as a missing pixel.
    ///
    /// Values appear exactly as EventHub emits them, which for a data parameter is the compact JSON the
    /// cases quote (`reason="overlay"`). Deliberately no percent-decoding: EventHub no longer encodes —
    /// the transport applies the wire's single encoding — and decoding here would corrupt a payload
    /// value that legitimately contains a `%`. The time-derived `attributionPeriod` is excluded, as the
    /// suites specify.
    var fired: [String] {
        fixture.fired.map { pixel in
            let parameters = pixel.parameters
                .filter { $0.key != "attributionPeriod" }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            return parameters.isEmpty ? pixel.name : "\(pixel.name)?\(parameters)"
        }
        .sorted()
    }

    /// Every conversion request handed to the experiment framework and accepted by it, written as
    /// `experiment/metric/window/threshold` and sorted — the shape of the metrics specification's
    /// derived-request table, so a case can state its complete expected set.
    var requested: [String] { fixture.requested }
}
