//
//  AdBlockingAvailability.swift
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

import Foundation
import BrowserServicesKit
import DuckPlayer
import PrivacyConfig
import WebExtensions

final class AdBlockingAvailability: AdBlockingAvailabilityProviding, ObservableObject {

    private let featureFlagger: FeatureFlagger
    private let isEnabledByUserProvider: () -> Bool

    /// In-memory session-scoped override. Resets naturally on cold launch because
    /// it lives only on this instance, which is constructed once at app startup.
    @Published private(set) var isDisabledUntilRelaunch: Bool = false

    init(featureFlagger: FeatureFlagger, isEnabledByUserProvider: @escaping () -> Bool) {
        self.featureFlagger = featureFlagger
        self.isEnabledByUserProvider = isEnabledByUserProvider
    }

    var isFeatureAvailable: Bool {
        guard #available(iOS 18.4, *) else { return false }
        return featureFlagger.isFeatureOn(.webExtensions)
            && featureFlagger.isFeatureOn(.adBlockingExtension)
    }
    var isEnabledByUser: Bool { isEnabledByUserProvider() }

    // TODO: Replace this UserDefaults-backed placeholder with the real derivation
    // (likely `!isFeatureAvailable && wasRolledOutByDefault`, or a dedicated
    // privacy-config flag — to be confirmed with privacy/growth).
    // When wiring the real flag, also observe its `true -> false` transition and
    // clear `YouTubeAdBlockingKeys.youTubeAdBlockUnavailableNoticeShown` so that
    // a subsequent re-disable surfaces the "YouTube Ad Block Unavailable" sheet
    // again for users who kept the app alive across the incident cycle.
    var isRemotelyDisabled: Bool {
        UserDefaults.standard.bool(forKey: Self.remotelyDisabledOverrideKey)
    }

    static let remotelyDisabledOverrideKey = "com.duckduckgo.ios.adBlocking.remotelyDisabledOverride"

    func disableUntilRelaunch() {
        guard !isDisabledUntilRelaunch else { return }
        isDisabledUntilRelaunch = true
        NotificationCenter.default.post(
            name: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification,
            object: nil
        )
    }

    func clearDisableUntilRelaunch() {
        guard isDisabledUntilRelaunch else { return }
        isDisabledUntilRelaunch = false
        NotificationCenter.default.post(
            name: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification,
            object: nil
        )
    }

    func shouldShowAnimation(for url: URL) -> Bool {
        isEnabled && url.isPlayableYoutubeVideoContent
    }
}
