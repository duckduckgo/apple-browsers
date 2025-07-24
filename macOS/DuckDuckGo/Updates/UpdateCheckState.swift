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

/// Actor responsible for managing update check state and task coordination.
///
/// Handles rate limiting, task lifecycle management, and prevents concurrent update checks.
/// Each UpdateController instance has its own UpdateCheckState for isolated state management.
/// 
actor UpdateCheckState {

    /// Default minimum interval between update checks
    static let defaultMinimumCheckInterval: TimeInterval = .minutes(5)

    private var activeUpdateTask: Task<Void, Never>?
    private var lastUpdateCheckTime: Date?

    /// Determines whether a new update check can be started.
    ///
    /// - Parameter minimumInterval: Minimum time interval that must pass between checks.
    ///   Defaults to `UpdateCheckState.defaultMinimumCheckInterval`.
    /// - Returns: `true` if no task is active and enough time has passed since the last check, `false` otherwise.
    ///
    func canStartNewCheck(minimumInterval: TimeInterval = UpdateCheckState.defaultMinimumCheckInterval) -> Bool {
        // Check if there's an active task
        if let task = activeUpdateTask, !task.isCancelled {
            return false
        }

        // Check if last check was less than the specified interval ago
        if let lastCheck = lastUpdateCheckTime,
           Date().timeIntervalSince(lastCheck) < minimumInterval {
            return false
        }

        return true
    }

    /// Cancels any currently active update task.
    ///
    /// This method immediately cancels the active task and clears the task reference.
    /// Used when user-initiated update checks need to take priority over automatic checks.
    ///
    internal func cancelActiveTask() {
        activeUpdateTask?.cancel()
        activeUpdateTask = nil
    }

    /// Sets or clears the currently active update task.
    ///
    /// - Parameter task: The task to track as active, or `nil` to clear the active task.
    ///
    internal func setActiveTask(_ task: Task<Void, Never>?) {
        activeUpdateTask = task
    }

    /// Records the current time as the last update check time.
    ///
    /// Used for rate limiting to ensure update checks don't happen too frequently.
    ///
    internal func recordCheckTime() {
        lastUpdateCheckTime = Date()
    }
}
