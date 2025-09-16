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

#if SPARKLE
import Sparkle
#endif

/// Protocol abstracting updater capabilities for update checking.
///
/// This protocol allows UpdateCheckState to work with different updater implementations
/// (Sparkle, App Store, etc.) without being tightly coupled to any specific framework.
protocol UpdaterAvailabilityChecking {
    /// Whether the updater is currently available for checking updates
    var canCheckForUpdates: Bool { get }
}

/// Actor responsible for managing update check state and rate limiting.
///
/// Handles rate limiting to prevent concurrent update checks.
/// Each UpdateController instance has its own UpdateCheckState for isolated state management.
/// 
actor UpdateCheckState {

    /// Default minimum interval between update checks
    static let defaultMinimumCheckInterval: TimeInterval = .minutes(5)

    private var lastUpdateCheckTime: Date?

    /// Determines whether a new update check can be started.
    ///
    /// - Parameters:
    ///   - updater: The updater instance to check for availability (must conform to UpdaterAvailabilityChecking)
    ///   - minimumInterval: Minimum time interval that must pass between checks.
    ///     Defaults to `UpdateCheckState.defaultMinimumCheckInterval`.
    /// - Returns: `true` if the updater allows checks and enough time has passed since the last check, `false` otherwise.
    ///
    func canStartNewCheck(updater: UpdaterAvailabilityChecking?, minimumInterval: TimeInterval = UpdateCheckState.defaultMinimumCheckInterval) -> Bool {
        // Check if updater allows checking for updates
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

    /// Records the current time as the last update check time.
    ///
    /// Used for rate limiting to ensure update checks don't happen too frequently.
    ///
    internal func recordCheckTime() {
        lastUpdateCheckTime = Date()
    }
}

// MARK: - SPUUpdater Conformance

#if SPARKLE
extension SPUUpdater: UpdaterAvailabilityChecking {
    // SPUUpdater already has canCheckForUpdates property, so no implementation needed
}
#endif
