//
//  YouTubeAdBlockingTelemetryConsentRequirement.swift
//  DuckDuckGo
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

import Combine
import EventHub
import Foundation
import Persistence

/// Gates the migrated YouTube ad-blocking-detection telemetry configs behind the user's YouTube
/// analytics opt-in (`YouTubeAdBlockingKeys.youTubeAnalyticsEnabled`).
///
/// The opt-in lives in the app's file-backed key-value store, which — unlike macOS' `UserDefaults` —
/// deliberately does not conform to `ObservableThrowingKeyValueStoring`, so there is no store-level
/// change publisher to observe. Writers post `youTubeAnalyticsEnabledDidChangeNotification` instead and
/// this re-reads the store on each one. `removeDuplicates` keeps a write that lands on the value already
/// stored — the ad-blocking toggle cascades into this setting whether or not it changes — from
/// needlessly churning EventHub's config.
final class YouTubeAdBlockingTelemetryConsentRequirement: EventHubConsentRequirement {

    let consentID = "youTubeAdBlockingAnalytics"
    let configNames: Set<String>
    let isGrantedPublisher: AnyPublisher<Bool, Never>

    init(configNames: Set<String> = EventHubGatedConfigNames.youTubeAdBlockingTelemetry,
         keyValueStore: ThrowingKeyValueStoring,
         notificationCenter: NotificationCenter = .default) {
        self.configNames = configNames

        let storage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> = keyValueStore.throwingKeyedStoring()
        let isGranted = {
            (try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)) ?? false
        }

        // The store is read at emission time, not here: `prepend` seeds the Void stream so that every
        // subscriber — whenever it subscribes — gets the value current at that moment, as
        // `EventHubConsentRequirement` requires.
        isGrantedPublisher = notificationCenter
            .publisher(for: YouTubeAdBlockingStorageKeys.youTubeAnalyticsEnabledDidChangeNotification)
            .map { _ in () }
            .prepend(())
            .map { _ in isGranted() }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
