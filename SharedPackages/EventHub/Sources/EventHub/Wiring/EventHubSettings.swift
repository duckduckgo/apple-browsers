//
//  EventHubSettings.swift
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
import Combine
import os.log

/// The EventHub view of remote config: feature enablement plus the telemetry settings JSON with any
/// consent-gated entries already removed. EventHub consumes this instead of talking to remote config or
/// consent directly, keeping the manager consent-agnostic.
public protocol EventHubSettingsProviding {
    var enabledPublisher: AnyPublisher<Bool, Never> { get }
    /// The feature settings in the `[String: Any]` shape remote config already holds them in (BSK's
    /// `settings(for:)` returns `FeatureSettings = [String: Any]`), so no JSON round trip is needed to
    /// hand them over. `nil` means no settings are available and no telemetry may run.
    var settingsPublisher: AnyPublisher<[String: Any]?, Never> { get }
}

/// Combines the raw feature settings with the live consent state of every `EventHubConsentRequirement`,
/// removing the `telemetry` entries for any consent group that is not currently granted.
public final class EventHubSettings: EventHubSettingsProviding {
    public let enabledPublisher: AnyPublisher<Bool, Never>
    public let settingsPublisher: AnyPublisher<[String: Any]?, Never>

    public init(
        featureEnabledPublisher: AnyPublisher<Bool, Never>,
        featureSettingsPublisher: AnyPublisher<[String: Any]?, Never>,
        consentRequirements: [EventHubConsentRequirement]
    ) {
        self.enabledPublisher = featureEnabledPublisher
        self.settingsPublisher = Publishers.CombineLatest(featureSettingsPublisher, Self.suppressedNames(consentRequirements))
            .map(Self.strip)
            .eraseToAnyPublisher()
    }

    private static func suppressedNames(_ requirements: [EventHubConsentRequirement]) -> AnyPublisher<Set<String>, Never> {
        guard !requirements.isEmpty else {
            return Just(Set<String>()).eraseToAnyPublisher()
        }
        let perRequirement = requirements.map { requirement in
            requirement.isGrantedPublisher.map { (requirement.configNames, $0) }.eraseToAnyPublisher()
        }
        let combined = perRequirement.dropFirst().reduce(perRequirement[0].map { [$0] }.eraseToAnyPublisher()) { accumulated, next in
            accumulated.combineLatest(next).map { $0 + [$1] }.eraseToAnyPublisher()
        }
        return combined
            .map { states in Set(states.filter { !$0.1 }.flatMap(\.0)) }
            .eraseToAnyPublisher()
    }

    private static func strip(_ settings: [String: Any]?, suppressed: Set<String>) -> [String: Any]? {
        guard !suppressed.isEmpty, var settings else { return settings }
        let key = EventHubConfigParser.telemetryKey
        // Fail closed: if we cannot reach the telemetry map to remove a gated entry from it, expose no
        // telemetry at all rather than risk collecting without consent.
        guard var telemetry = settings[key] as? [String: Any] else {
            Logger.eventHub.error("settings: consent stripping found no usable `\(key, privacy: .public)` object, failing closed")
            return nil
        }
        for name in suppressed { telemetry.removeValue(forKey: name) }
        settings[key] = telemetry
        return settings
    }
}
