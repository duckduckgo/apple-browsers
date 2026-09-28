//
//  PerformanceOptimizedPaywallsProvider.swift
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
import PrivacyConfig
import Subscription

/// Provides utilities to query the `performanceOptimizedPaywalls` subfeature.
public protocol PerformanceOptimizedPaywallsProviding {
    /// Indicates whether the pre-rendered paywalls should be used.
    var isEnabled: Bool { get }

    /// The paths of the pre-rendered paywall pages.
    var paths: SubscriptionURL.PerformanceOptimizedPaywallPaths { get }
}

/// Provides the rollout state for performance-optimized paywalls.
public protocol PerformanceOptimizedPaywallsFeatureFlagging {
    var isPerformanceOptimizedPaywallsEnabled: Bool { get }
}

/// Default implementation of `PerformanceOptimizedPaywallsProviding`.
///
/// The paths come from the subfeature's settings so the frontend can move the pages without an app
/// release. Each path falls back independently, so a config that carries only one of them still works.
public struct DefaultPerformanceOptimizedPaywallsProvider: PerformanceOptimizedPaywallsProviding {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let featureFlagger: any PerformanceOptimizedPaywallsFeatureFlagging
    private let fallbackPaths: SubscriptionURL.PerformanceOptimizedPaywallPaths

    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                featureFlagger: any PerformanceOptimizedPaywallsFeatureFlagging,
                fallbackPaths: SubscriptionURL.PerformanceOptimizedPaywallPaths = .default) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.featureFlagger = featureFlagger
        self.fallbackPaths = fallbackPaths
    }

    public var isEnabled: Bool {
        featureFlagger.isPerformanceOptimizedPaywallsEnabled
    }

    public var paths: SubscriptionURL.PerformanceOptimizedPaywallPaths {
        guard let settingsString = privacyConfigurationManager.privacyConfig.settings(for: PrivacyProSubfeature.performanceOptimizedPaywalls),
              let settingsData = settingsString.data(using: .utf8),
              let settings = try? JSONDecoder().decode(Settings.self, from: settingsData) else {
            return fallbackPaths
        }

        return SubscriptionURL.PerformanceOptimizedPaywallPaths(
            vpn: settings.entryPoints?.vpn?.path ?? fallbackPaths.vpn,
            duckai: settings.entryPoints?.duckai?.path ?? fallbackPaths.duckai,
            pir: settings.entryPoints?.pir?.path ?? fallbackPaths.pir
        )
    }

    private struct Settings: Decodable {

        struct EntryPoint: Decodable {
            let path: String?
        }

        struct EntryPoints: Decodable {
            let vpn: EntryPoint?
            let duckai: EntryPoint?
            let pir: EntryPoint?
        }

        let entryPoints: EntryPoints?
    }
}
