//
//  AdBlockingAvailabilityProviding.swift
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

/// Protocol for checking ad-blocking feature availability.
/// Implemented by platform-specific classes (iOS and macOS) to determine
/// whether the ad-blocking extension feature is available and enabled by the user.
public protocol AdBlockingAvailabilityProviding {
    /// Whether the underlying platform supports the ad-blocking extension at all
    /// (OS version + web-extensions feature flag). Independent of the rollout flag —
    /// stays `true` even while the feature is in contingency mode.
    var isFeatureSupported: Bool { get }

    /// Whether the user has enabled ad-blocking in settings
    var isEnabledByUser: Bool { get }

    /// Whether ad-blocking is fully enabled (platform supports, not remotely disabled,
    /// user opted in, and not disabled until relaunch).
    var isEnabled: Bool { get }

    /// Whether the feature has been remotely disabled via privacy config. Drives the
    /// "Unavailable" contingency UI; assumed to surface for every supported user.
    var isRemotelyDisabled: Bool { get }

    /// Whether the user has disabled ad-blocking for the current app session via the
    /// browsing-menu picker. Resets on cold launch.
    var isDisabledUntilRelaunch: Bool { get }

    /// Whether the `adBlockingExtensionEnabledByDefault` rollout has activated the new
    /// defaults regime for this user. Temporary helper for the rollout window —
    /// consumers compose this into their nil-fallbacks to derive the correct
    /// `youTubeAdBlockingEnabled` default.
    var areAdBlockingDefaultsActive: Bool { get }

    /// Default value for `youTubeAdBlockingEnabled` when the user has no stored choice.
    /// Mirrors `areAdBlockingDefaultsActive`.
    var defaultYouTubeAdBlockingEnabled: Bool { get }

    /// Mark ad-blocking as disabled until the next app launch.
    func disableUntilRelaunch()

    /// Clear the disable-until-relaunch override (called when the user re-enables explicitly).
    func clearDisableUntilRelaunch()

    /// Whether the ad-block animation should be shown for the given URL.
    /// Platform conformances use this to add URL-specific checks (e.g., YouTube video pages).
    func shouldShowAnimation(for url: URL) -> Bool
}

extension AdBlockingAvailabilityProviding {
    public var isEnabled: Bool {
        isFeatureSupported && !isRemotelyDisabled && isEnabledByUser && !isDisabledUntilRelaunch
    }
    public var isRemotelyDisabled: Bool { false }
    public var isDisabledUntilRelaunch: Bool { false }
    public var areAdBlockingDefaultsActive: Bool { false }
    public var defaultYouTubeAdBlockingEnabled: Bool { areAdBlockingDefaultsActive }
    public func disableUntilRelaunch() {}
    public func clearDisableUntilRelaunch() {}
}
