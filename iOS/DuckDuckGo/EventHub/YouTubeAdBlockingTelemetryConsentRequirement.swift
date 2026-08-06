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
/// Ad Blocking *and* analytics opt-ins, matching both the composite check the retired
/// `WebEventsSubfeature` applied per event and the macOS requirement.
///
/// Both flags are required deliberately, rather than relying on analytics alone. Turning YouTube Ad
/// Blocking off does clear the analytics opt-in, but on iOS that coupling is an explicit cascade at two
/// call sites (`SettingsViewModel.setYouTubeAnalyticsEnabled` and
/// `MainViewController.setYouTubeAdBlockingEnabled`) — even weaker than macOS' `didSet`, since any write
/// that bypasses them, such as the ad-blocking debug screen, leaves analytics granted. The two flags are
/// independently writable with no storage-level invariant tying them together, so a consent gate must not
/// depend on the cascade having run.
///
/// Neither flag can be observed directly: they live in the app's file-backed key-value store, which —
/// unlike macOS' `UserDefaults` — deliberately does not conform to `ObservableThrowingKeyValueStoring`.
/// Writers post the two `…DidChangeNotification`s instead, and this re-reads both values on either one.
/// `removeDuplicates` keeps a write that lands on the value already stored from needlessly churning
/// EventHub's config.
final class YouTubeAdBlockingTelemetryConsentRequirement: EventHubConsentRequirement {

    let consentID = "youTubeAdBlockingAnalytics"
    let configNames: Set<String>
    let isGrantedPublisher: AnyPublisher<Bool, Never>

    init(configNames: Set<String> = EventHubGatedConfigNames.youTubeAdBlockingTelemetry,
         keyValueStore: ThrowingKeyValueStoring,
         notificationCenter: NotificationCenter = .default) {
        self.configNames = configNames

        let storage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> = keyValueStore.throwingKeyedStoring()
        // An unset flag counts as withheld. This deliberately ignores the `adBlockingExtensionEnabledByDefault`
        // rollout default that `AdBlockingAvailability` applies to `youTubeAdBlockingEnabled`: consulting it
        // here would make consent depend on a remote flag and could fail open, and failing closed only ever
        // withholds telemetry.
        let isGranted = {
            let adBlockingEnabled = (try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled)) ?? false
            let analyticsEnabled = (try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)) ?? false
            return adBlockingEnabled && analyticsEnabled
        }

        // The store is read at emission time, not here: `prepend` seeds the Void stream so that every
        // subscriber — whenever it subscribes — gets the value current at that moment, as
        // `EventHubConsentRequirement` requires.
        isGrantedPublisher = notificationCenter
            .publisher(for: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification)
            .map { _ in () }
            .merge(with: notificationCenter
                .publisher(for: YouTubeAdBlockingStorageKeys.youTubeAnalyticsEnabledDidChangeNotification)
                .map { _ in () })
            .prepend(())
            .map { _ in isGranted() }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
