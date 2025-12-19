//
//  HangReportingFeatureMonitor.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import FeatureFlags
import Foundation
import PrivacyConfig

/// Monitors the hangReporting feature flag and notifies the Watchdog when it changes.
///
final class HangReportingFeatureMonitor {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let featureFlagger: FeatureFlagger
    private let watchdog: Watchdog
    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - privacyConfigurationManager: The privacy configuration manager to monitor for updates
    ///   - featureFlagger: The feature flagger to check the hangReporting feature flag state.
    ///                    The monitor will check `.hangReporting` which respects local overrides while also reflecting remote config values.
    ///   - watchdog: The watchdog instance to start/stop based on feature flag changes
    init(privacyConfigurationManager: PrivacyConfigurationManaging,
         featureFlagger: FeatureFlagger,
         watchdog: Watchdog) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.featureFlagger = featureFlagger
        self.watchdog = watchdog

        // Subscribe to privacy configuration updates to respond to remote config changes.
        // Map to the feature flag state and remove duplicates to avoid redundant start/stop calls
        // when the config reloads multiple times but the value doesn't actually change.
        cancellable = privacyConfigurationManager.updatesPublisher
            .prepend(()) // Get initial value immediately
            .map { [featureFlagger] _ in featureFlagger.isFeatureOn(FeatureFlag.hangReporting) }
            .removeDuplicates() // Only proceed if the value actually changed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self = self else { return }

                Task {
                    if isEnabled {
                        await self.watchdog.start()
                    } else {
                        await self.watchdog.stop()
                    }
                }
            }
    }

    deinit {
        cancellable?.cancel()
    }
}
