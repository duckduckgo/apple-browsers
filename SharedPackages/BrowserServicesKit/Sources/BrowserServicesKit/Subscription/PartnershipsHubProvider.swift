//
//  PartnershipsHubProvider.swift
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

/// Provides utilities to query the `partnershipsHub` subfeature, which backs the Subscriber Offers
/// settings entry point.
///
/// Whether the entry point is actually shown is up to the caller: this only answers the remote-config
/// half of the question, and every platform additionally requires an active subscription.
public protocol PartnershipsHubProviding {
    /// Indicates whether the Subscriber Offers entry point is enabled in remote config.
    var isEntryPointEnabled: Bool { get }

    /// The Partnerships Hub URL the entry point opens. Always an absolute https URL.
    var hubURL: URL { get }

    /// Indicates whether the NEW badge should be shown on the entry point.
    var showsNewBadge: Bool { get }
}

/// Provides the rollout state for the Subscriber Offers entry point.
public protocol PartnershipsHubFeatureFlagging {
    var isPartnershipsHubEnabled: Bool { get }
}

/// Default implementation of `PartnershipsHubProviding`.
///
/// The hub URL comes from the subfeature's settings so the frontend can move the page without an app
/// release, and uses the same `url` key as Android and Windows so one remote config change covers
/// every platform. It falls back to `fallbackURL` unless the remote value is an absolute https URL:
/// call sites navigate to it directly, so a malformed remote value must not reach them.
public struct DefaultPartnershipsHubProvider: PartnershipsHubProviding {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let featureFlagger: any PartnershipsHubFeatureFlagging
    private let fallbackURL: () -> URL

    /// - Parameter fallbackURL: The compiled-in default, evaluated on each read because it depends on
    ///   the current subscription environment (`SubscriptionURL.partnershipsHub`), which an internal
    ///   user can change at runtime.
    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                featureFlagger: any PartnershipsHubFeatureFlagging,
                fallbackURL: @escaping () -> URL) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.featureFlagger = featureFlagger
        self.fallbackURL = fallbackURL
    }

    public var isEntryPointEnabled: Bool {
        featureFlagger.isPartnershipsHubEnabled
    }

    public var hubURL: URL {
        guard let urlString = settings?.url,
              let url = URL(string: urlString),
              url.scheme == "https",
              url.host?.isEmpty == false else {
            return fallbackURL()
        }
        return url
    }

    /// On unless remote config turns it off, matching the other platforms.
    public var showsNewBadge: Bool {
        settings?.showNewPill ?? true
    }

    private var settings: Settings? {
        guard let settingsString = privacyConfigurationManager.privacyConfig.settings(for: PrivacyProSubfeature.partnershipsHub),
              let settingsData = settingsString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(Settings.self, from: settingsData)
    }

    private struct Settings: Decodable {
        let url: String?
        let showNewPill: Bool?
    }
}
