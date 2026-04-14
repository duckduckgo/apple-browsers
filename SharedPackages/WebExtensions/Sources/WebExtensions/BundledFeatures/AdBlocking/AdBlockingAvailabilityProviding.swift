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
    /// Whether the ad-blocking extension feature flag is enabled
    var isFeatureAvailable: Bool { get }

    /// Whether the user has enabled ad-blocking in settings
    var isEnabledByUser: Bool { get }

    /// Whether ad-blocking is fully enabled (feature available AND user opted in)
    var isEnabled: Bool { get }

    /// Whether the ad-block animation should be shown for the given URL.
    /// Platform conformances use this to add URL-specific checks (e.g., YouTube video pages).
    func shouldShowAnimation(for url: URL) -> Bool
}

extension AdBlockingAvailabilityProviding {
    public var isEnabled: Bool { isFeatureAvailable && isEnabledByUser }
}
