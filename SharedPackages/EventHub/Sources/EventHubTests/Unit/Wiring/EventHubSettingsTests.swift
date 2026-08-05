//
//  EventHubSettingsTests.swift
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
import Combine
@testable import EventHub

@Suite("EventHubSettings")
struct EventHubSettingsTests {
    static let settings = settingsDictionary("""
    { "telemetry": {
        "gated_pixel":   { "state": "enabled", "trigger": { "type": "period", "period": { "seconds": 60 } } },
        "ungated_pixel": { "state": "enabled", "trigger": { "type": "period", "period": { "seconds": 60 } } }
    } }
    """)

    private static func telemetryKeys(_ settings: [String: Any]?) -> [String] {
        let telemetry = settings?[EventHubConfigParser.telemetryKey] as? [String: Any] ?? [:]
        return telemetry.keys.sorted()
    }

    private final class FakeConsentRequirement: EventHubConsentRequirement {
        let consentID = "test"
        let configNames: Set<String> = ["gated_pixel"]
        let granted = CurrentValueSubject<Bool, Never>(false)
        var isGrantedPublisher: AnyPublisher<Bool, Never> { granted.eraseToAnyPublisher() }
    }

    @Test("removes the gated config while consent is withheld")
    func removesGatedConfigWhileConsentIsWithheld() {
        let requirement = FakeConsentRequirement()
        let subject = EventHubSettings(
            featureEnabledPublisher: Just(true).eraseToAnyPublisher(),
            featureSettingsPublisher: Just(Self.settings as [String: Any]?).eraseToAnyPublisher(),
            consentRequirements: [requirement])

        var latest: [String: Any]?
        let cancellable = subject.settingsPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        #expect(Self.telemetryKeys(latest) == ["ungated_pixel"])

        requirement.granted.send(true)
        #expect(Self.telemetryKeys(latest) == ["gated_pixel", "ungated_pixel"])
    }

    /// Regression guard: "eventHub enabled, nothing configured yet" is the normal pre-rollout state. It
    /// holds no gated data, so failing closed on it would black out all telemetry — and fire the debug
    /// event — for every install running a config that has not reached the rollout yet.
    @Test("settings without a telemetry key pass through untouched and fire nothing")
    func settingsWithoutTelemetryKeyPassThroughUntouchedAndFireNothing() {
        let capture = CapturingEventMapping()
        let subject = EventHubSettings(
            featureEnabledPublisher: Just(true).eraseToAnyPublisher(),
            featureSettingsPublisher: Just(["other": "value"] as [String: Any]?).eraseToAnyPublisher(),
            consentRequirements: [FakeConsentRequirement()],
            eventMapping: capture.eventMapping)

        var latest: [String: Any]?
        let cancellable = subject.settingsPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        #expect(latest?["other"] as? String == "value")
        #expect(capture.fired.isEmpty)
    }

    @Test("telemetry in a shape that cannot be stripped fails closed and reports it")
    func telemetryInUnstrippableShapeFailsClosedAndReportsIt() {
        let capture = CapturingEventMapping()
        let subject = EventHubSettings(
            featureEnabledPublisher: Just(true).eraseToAnyPublisher(),
            featureSettingsPublisher: Just([EventHubConfigParser.telemetryKey: "not an object"] as [String: Any]?).eraseToAnyPublisher(),
            consentRequirements: [FakeConsentRequirement()],
            eventMapping: capture.eventMapping)

        var latest: [String: Any]?
        var received = false
        let cancellable = subject.settingsPublisher.sink { latest = $0; received = true }
        defer { cancellable.cancel() }

        #expect(received)
        #expect(latest == nil)
        #expect(capture.fired == [.consentStripFailed])
    }
}
