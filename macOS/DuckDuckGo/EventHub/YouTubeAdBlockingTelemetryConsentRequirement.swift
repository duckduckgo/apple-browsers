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
/// analytics opt-in (`YouTubeAdBlockingSettings.youTubeAnalyticsEnabled`).
final class YouTubeAdBlockingTelemetryConsentRequirement: EventHubConsentRequirement {

    let consentID = "youTubeAdBlockingAnalytics"
    let configNames: Set<String>
    let isGrantedPublisher: AnyPublisher<Bool, Never>

    init(configNames: Set<String>, store: any ObservableKeyValueStoring = UserDefaults.standard) {
        self.configNames = configNames
        let settings: any ObservableKeyedStoring<YouTubeAdBlockingSettings> = store.observableKeyedStoring()
        isGrantedPublisher = settings.publisher(for: \.youTubeAnalyticsEnabled)
            .map { $0 ?? false }
            .eraseToAnyPublisher()
    }
}
