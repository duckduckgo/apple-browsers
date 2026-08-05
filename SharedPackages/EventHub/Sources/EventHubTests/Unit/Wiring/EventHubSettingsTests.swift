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
}
