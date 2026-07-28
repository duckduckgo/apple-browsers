//
//  MacOSEventHubIntegration.swift
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
import os.log
import Persistence
import PrivacyConfig

/// Owns and wires up the macOS `EventHub` instance: remote-config bridging, persistence, scheduling,
/// pixel firing, and consent gating. Constructed once by `AppDelegate`.
final class MacOSEventHubIntegration {

    /// The `telemetry` config names (keys in the remote eventHub settings) gated behind the YouTube
    /// analytics opt-in. These must byte-match the server-side config keys: a mismatch fails open — the
    /// entry is never stripped, so its telemetry would be collected without consent.
    private static let youTubeAdBlockingTelemetryConfigNames: Set<String> = [
        "webTelemetry_youtube_adBlocker_day",
        "webTelemetry_youtube_playabilityError_day",
        "webTelemetry_youtube_videoAd_day",
        "webTelemetry_youtube_staticAd_day",
        "webTelemetry_youtube_buffering_day"
    ]

    let eventHub: EventHubManaging

    private var cancellables = Set<AnyCancellable>()

    init(privacyConfigurationManager: PrivacyConfigurationManaging, keyValueStore: ThrowingKeyValueStoring) {
        let parser = EventHubConfigParser()
        let store = EventHubKeyValueStore(store: keyValueStore, parser: parser)

        let enabledSubject = CurrentValueSubject<Bool, Never>(
            privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .eventHub))
        let settingsSubject = CurrentValueSubject<[String: Any]?, Never>(
            privacyConfigurationManager.privacyConfig.settings(for: PrivacyFeature.eventHub))

        let settings = EventHubSettings(
            featureEnabledPublisher: enabledSubject.eraseToAnyPublisher(),
            featureSettingsPublisher: settingsSubject.eraseToAnyPublisher(),
            consentRequirements: [
                YouTubeAdBlockingTelemetryConsentRequirement(configNames: Self.youTubeAdBlockingTelemetryConfigNames)
            ]
        )

        let eventHub = EventHub(
            store: store,
            parser: parser,
            settings: settings,
            scheduler: DispatchQueueEventHubScheduler(queue: DispatchQueue(label: "com.duckduckgo.eventhub.scheduler")),
            pixelFiring: MacOSEventHubPixelFiring()
        )
        self.eventHub = eventHub

        // Pushing the new values is all that is needed: `EventHub` subscribes to both publishers and
        // re-applies its config whenever either emits, so there is no explicit `onConfigChanged()` call
        // to keep in sync here. The same holds for consent changes, which reach `EventHub` through
        // `EventHubSettings`' settings publisher rather than through this subscription.
        privacyConfigurationManager.updatesPublisher
            .sink { [weak privacyConfigurationManager] in
                guard let privacyConfigurationManager else { return }
                let enabled = privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .eventHub)
                Logger.eventHub.debug("Remote config updated — pushing to EventHub (enabled=\(enabled, privacy: .public))")
                enabledSubject.send(enabled)
                settingsSubject.send(privacyConfigurationManager.privacyConfig.settings(for: PrivacyFeature.eventHub))
            }
            .store(in: &cancellables)
    }

    func applicationDidBecomeActive() {
        eventHub.onAppForegrounded()
    }

    func applicationDidResignActive() {
        eventHub.onAppBackgrounded()
    }
}
