//
//  UpdateProgressState.swift
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

#if SPARKLE

import Combine
import Foundation

/// Protocol for managing update progress state transitions.
protocol UpdateProgressManaging: AnyObject {
    var updateProgress: UpdateCycleProgress { get }
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { get }

    /// Attempt to transition to a new state. Returns false if transition was rejected.
    @discardableResult
    func transition(to newProgress: UpdateCycleProgress) -> Bool

    /// Reset state for a new update cycle
    func reset()

    // Computed convenience properties
    var isAtRestartCheckpoint: Bool { get }
    var isAtDownloadCheckpoint: Bool { get }
}

/// Concrete implementation of update progress state management.
///
/// Encapsulates state transition logic, ensuring invalid transitions are rejected
/// (e.g., don't overwrite error state with "dismissed").
final class UpdateProgressState: UpdateProgressManaging {
    @Published private(set) var updateProgress = UpdateCycleProgress.default
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    @discardableResult
    func transition(to newProgress: UpdateCycleProgress) -> Bool {
        // Don't overwrite error state with "dismissed"
        if case .updaterError = updateProgress,
           case .updateCycleDone(.dismissedWithNoError) = newProgress {
            return false
        }

        updateProgress = newProgress
        return true
    }

    func reset() {
        updateProgress = .updateCycleNotStarted
    }

    var isAtRestartCheckpoint: Bool {
        switch updateProgress {
        case .readyToInstallAndRelaunch:
            return true
        case .updateCycleDone(let reason) where reason == .pausedAtRestartCheckpoint:
            return true
        default:
            return false
        }
    }

    var isAtDownloadCheckpoint: Bool {
        if case .updateCycleDone(let reason) = updateProgress,
           reason == .pausedAtDownloadCheckpoint {
            return true
        }
        return false
    }
}

#endif
