//
//  YouTubeAdBlockingTelemetryConsentRequirement.swift
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
/// Ad Blocking *and* analytics opt-ins, matching the composite check the retired `WebEventsSubfeature`
/// applied per event.
///
/// Both flags are required deliberately, rather than relying on analytics alone. Turning YouTube Ad
/// Blocking off does clear the analytics opt-in, but that coupling is a `didSet` side effect in
/// `YouTubeAdBlockingPreferences` — it only runs while an instance of that model exists and the value
/// actually changes. The two flags are independently writable defaults with no storage-level invariant
/// tying them together, so a consent gate must not depend on that side effect having run.
final class YouTubeAdBlockingTelemetryConsentRequirement: EventHubConsentRequirement {

    let consentID = "youTubeAdBlockingAnalytics"
    let configNames: Set<String>
    let isGrantedPublisher: AnyPublisher<Bool, Never>

    init(configNames: Set<String>, store: any ObservableKeyValueStoring = UserDefaults.standard) {
        self.configNames = configNames
        let settings: any ObservableKeyedStoring<YouTubeAdBlockingSettings> = store.observableKeyedStoring()
        isGrantedPublisher = settings.publisher(for: \.youTubeAdBlockingEnabled)
            .combineLatest(settings.publisher(for: \.youTubeAnalyticsEnabled))
            .map { ($0 ?? false) && ($1 ?? false) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
