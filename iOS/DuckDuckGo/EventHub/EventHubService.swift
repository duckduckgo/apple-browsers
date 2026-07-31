//
//  EventHubService.swift
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
import os.log
import Persistence
import PrivacyConfig

/// Owns and wires up the iOS `EventHub` instance: remote-config bridging, persistence, scheduling,
/// pixel firing, and consent gating. Constructed once during `Launching` and held by `AppServices`.
final class EventHubService {

    let eventHub: EventHubManaging

    private var cancellables = Set<AnyCancellable>()

    init(privacyConfigurationManager: PrivacyConfigurationManaging, keyValueStore: ThrowingKeyValueStoring) {
        let parser = EventHubConfigParser()
        let store = EventHubKeyValueStore(store: keyValueStore, parser: parser)

        let enabledSubject = CurrentValueSubject<Bool, Never>(
            privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .eventHub))
        let settingsSubject = CurrentValueSubject<Data?, Never>(
            Self.settingsData(from: privacyConfigurationManager))

        let settings = EventHubSettings(
            featureEnabledPublisher: enabledSubject.eraseToAnyPublisher(),
            featureSettingsPublisher: settingsSubject.eraseToAnyPublisher(),
            consentRequirements: [
                YouTubeAdBlockingTelemetryConsentRequirement(keyValueStore: keyValueStore)
            ]
        )

        eventHub = EventHub(
            store: store,
            parser: parser,
            settings: settings,
            scheduler: DispatchQueueEventHubScheduler(queue: DispatchQueue(label: "com.duckduckgo.eventhub.scheduler")),
            pixelFiring: IOSEventHubPixelFiring()
        )

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
                settingsSubject.send(Self.settingsData(from: privacyConfigurationManager))
            }
            .store(in: &cancellables)
    }

    func resume() {
        eventHub.onAppForegrounded()
    }

    /// Backgrounding is EventHub's flush boundary. Unlike macOS there is no separate termination hook to
    /// mirror it: iOS always moves the app to the background before terminating it, so this is reached on
    /// the way out of every quit.
    func suspend() {
        eventHub.onAppBackgrounded()
    }

    private static func settingsData(from privacyConfigurationManager: PrivacyConfigurationManaging) -> Data? {
        try? JSONSerialization.data(withJSONObject: privacyConfigurationManager.privacyConfig.settings(for: PrivacyFeature.eventHub))
    }
}
