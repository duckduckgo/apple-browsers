//
//  UpdateCheckState.swift
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

import Foundation
import Sparkle

/// Actor responsible for managing update check state and rate limiting.
///
/// Handles rate limiting to prevent concurrent update checks.
/// Each UpdateController instance has its own UpdateCheckState for isolated state management.
/// 
actor UpdateCheckState {

    /// Default minimum interval between update checks
    static let defaultMinimumCheckInterval: TimeInterval = .minutes(5)

    private var lastUpdateCheckTime: Date?

    /// Core logic for determining if an update check can start.
    ///
    /// - Parameters:
    ///   - updater: The SPUUpdater instance to check for availability
    ///   - minimumInterval: Minimum time interval that must pass between checks
    /// - Returns: `true` if Sparkle allows checks and enough time has passed since the last check, `false` otherwise.
    ///
    func canStartCheck(updater: SPUUpdater?, minimumInterval: TimeInterval) -> Bool {
        // Check if Sparkle allows checking for updates
        if let updater = updater, !updater.canCheckForUpdates {
            return false
        }

        // Check if last check was less than the specified interval ago
        if let lastCheck = lastUpdateCheckTime,
           Date().timeIntervalSince(lastCheck) < minimumInterval {
            return false
        }

        return true
    }

    /// Determines whether a new user-initiated update check can be started.
    ///
    /// User-initiated checks bypass rate limiting since they are explicitly requested by the user.
    ///
    /// - Parameter updater: The SPUUpdater instance to check for availability
    /// - Returns: `true` if Sparkle allows checks, `false` if another update session is in progress.
    ///
    func canStartUserInitiatedCheck(updater: SPUUpdater?) -> Bool {
        return canStartCheck(updater: updater, minimumInterval: 0)
    }

    /// Determines whether a new background update check can be started.
    ///
    /// Background checks respect rate limiting to prevent excessive requests.
    ///
    /// - Parameter updater: The SPUUpdater instance to check for availability
    /// - Returns: `true` if Sparkle allows checks and enough time has passed since the last check, `false` otherwise.
    ///
    func canStartBackgroundCheck(updater: SPUUpdater?) -> Bool {
        return canStartCheck(updater: updater, minimumInterval: UpdateCheckState.defaultMinimumCheckInterval)
    }

    /// Records the current time as the last update check time.
    ///
    /// Used for rate limiting to ensure update checks don't happen too frequently.
    ///
    internal func recordCheckTime() {
        lastUpdateCheckTime = Date()
    }
}
