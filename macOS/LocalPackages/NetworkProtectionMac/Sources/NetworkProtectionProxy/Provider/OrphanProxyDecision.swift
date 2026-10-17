//
//  OrphanProxyDecision.swift
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

/// The detector state the transparent proxy should hold after evaluating one observation.
struct OrphanProxyDecision: Equatable {

    /// Whether full-bypass mode should be on after this check.
    let isFullBypassEnabled: Bool

    /// The episode's fire-once latch after this check.
    let orphanFiredForCurrentEpisode: Bool

    /// Whether the "first orphan detection of this episode" pixel should fire now.
    let shouldFirePixel: Bool
}

/// Pure decision logic for the orphaned-proxy detector, extracted from `TransparentProxyProvider`
/// so it can be unit-tested without standing up a Network Extension provider.
///
/// The proxy records when it started and reads the tunnel's heartbeat timestamp; a proxy that has
/// been up past the age threshold while the heartbeat is stale (or absent) is treated as orphaned —
/// its tunnel is gone. Bypass engages so traffic falls back to default routing, and lifts again once
/// a fresh heartbeat shows the tunnel recovered.
enum OrphanProxyTester {

    /// Decides the next detector state from a single observation.
    ///
    /// Returns `nil` when the proxy is younger than `proxyAgeThreshold`, meaning the caller leaves
    /// all detector state untouched (too early to judge).
    ///
    /// - Parameters:
    ///   - proxyAge: How long the proxy has been running.
    ///   - heartbeatAge: Age of the tunnel's last heartbeat, or `nil` if none was ever recorded.
    ///   - bypassEnabled: The bypass kill switch — when `false`, an orphan is reported but bypass never engages.
    ///   - isFullBypassEnabled: Whether bypass is currently on.
    ///   - orphanFiredForCurrentEpisode: Whether the pixel already fired for the current orphan episode.
    ///   - proxyAgeThreshold: Minimum proxy age before we judge orphan status.
    ///   - heartbeatAgeThreshold: Maximum heartbeat age still considered fresh.
    static func decision(
        proxyAge: TimeInterval,
        heartbeatAge: TimeInterval?,
        bypassEnabled: Bool,
        isFullBypassEnabled: Bool,
        orphanFiredForCurrentEpisode: Bool,
        proxyAgeThreshold: TimeInterval,
        heartbeatAgeThreshold: TimeInterval
    ) -> OrphanProxyDecision? {
        guard proxyAge >= proxyAgeThreshold else { return nil }

        let heartbeatIsFresh: Bool
        if let heartbeatAge {
            heartbeatIsFresh = heartbeatAge < heartbeatAgeThreshold
        } else {
            heartbeatIsFresh = false
        }

        // Fresh heartbeat: the tunnel is alive, so lift any bypass and reset the episode latch.
        if heartbeatIsFresh {
            return OrphanProxyDecision(
                isFullBypassEnabled: false,
                orphanFiredForCurrentEpisode: false,
                shouldFirePixel: false)
        }

        // Stale heartbeat: orphaned. Engage bypass if the kill switch allows it, and fire the pixel
        // once per episode. The bypass decision is independent of the fire-once latch.
        return OrphanProxyDecision(
            isFullBypassEnabled: isFullBypassEnabled || bypassEnabled,
            orphanFiredForCurrentEpisode: true,
            shouldFirePixel: !orphanFiredForCurrentEpisode)
    }
}
