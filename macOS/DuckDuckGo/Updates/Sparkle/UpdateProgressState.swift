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
import os.log

/// Protocol for managing update progress state transitions.
protocol UpdateProgressManaging: AnyObject {
    var updateProgress: UpdateCycleProgress { get }
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { get }

    /// Attempt to transition to a new state. Returns false if transition was rejected.
    @discardableResult
    func transition(to newProgress: UpdateCycleProgress) -> Bool

    /// Attempt to transition to a new state with a resume callback.
    @discardableResult
    func transition(to newProgress: UpdateCycleProgress, resume: (() -> Void)?) -> Bool

    /// Reset state for a new update cycle
    func reset()

    // Computed convenience properties
    var isAtRestartCheckpoint: Bool { get }
    var isAtDownloadCheckpoint: Bool { get }
    var isResumable: Bool { get }
    var resumeCallback: (() -> Void)? { get }

    /// Handles progress changes from the driver - matches driver's expected callback signature
    func handleProgressChange(_ progress: UpdateCycleProgress, _ resume: (() -> Void)?)
}

/// Concrete implementation of update progress state management.
///
/// Encapsulates state transition logic, ensuring invalid transitions are rejected
/// (e.g., don't overwrite error state with "dismissed").
final class UpdateProgressState: UpdateProgressManaging {
    @Published private(set) var updateProgress = UpdateCycleProgress.default
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }
    private(set) var resumeCallback: (() -> Void)?

    var isResumable: Bool { resumeCallback != nil }

    private var isIdleOrTerminal: Bool {
        switch updateProgress {
        case .updateCycleNotStarted, .updaterError:
            return true
        case .updateCycleDone(let reason):
            switch reason {
            case .finishedWithNoError, .finishedWithNoUpdateFound, .dismissedWithNoError, .dismissingObsoleteUpdate:
                return true
            case .pausedAtDownloadCheckpoint, .pausedAtRestartCheckpoint, .proceededToInstallationAtRestartCheckpoint:
                return false
            }
        case .updateCycleDidStart, .downloadDidStart, .downloading, .extractionDidStart, .extracting,
             .readyToInstallAndRelaunch, .installationDidStart, .installing:
            return false
        }
    }

    @discardableResult
    func transition(to newProgress: UpdateCycleProgress) -> Bool {
        transition(to: newProgress, resume: nil)
    }

    @discardableResult
    func transition(to newProgress: UpdateCycleProgress, resume: (() -> Void)?) -> Bool {
        // Preserve error state so UI can show the error instead of clearing it
        if case .updaterError = updateProgress,
           case .updateCycleDone(.dismissedWithNoError) = newProgress {
            Logger.updates.debug("State transition rejected: cannot dismiss error state")
            return false
        }

        // Prevent new checks from disrupting pending updates (e.g., at restart checkpoint)
        if case .updateCycleDidStart = newProgress, !isIdleOrTerminal {
            Logger.updates.debug("State transition rejected: update already in progress")
            return false
        }

        Logger.updates.debug("State: \(String(describing: self.updateProgress), privacy: .public) -> \(String(describing: newProgress), privacy: .public)")
        // Set callback before updateProgress because @Published fires on willSet
        resumeCallback = resume
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

    func handleProgressChange(_ progress: UpdateCycleProgress, _ resume: (() -> Void)?) {
        transition(to: progress, resume: resume)
    }
}

#endif
