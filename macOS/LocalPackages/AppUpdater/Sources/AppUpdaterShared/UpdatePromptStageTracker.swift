//
//  UpdatePromptStageTracker.swift
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

import AppKit
import Combine
import ConcurrencyExtensions
import Foundation
import Persistence

/// How far along the prompt ramp a user who hasn't updated is.
public enum UpdatePromptStage: Int, Comparable, CaseIterable, Sendable {
    case none
    case available
    case firstPrompt
    case secondPrompt

    public static func < (lhs: UpdatePromptStage, rhs: UpdatePromptStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tracks the update prompt stage from a persisted clock that starts at the first check finding a newer version (day 0).
///
/// The clock survives relaunches and newer releases, and is cleared when the installed version changes
/// or a check no longer finds an update. Critical updates go straight to `.secondPrompt`.
@MainActor
public final class UpdatePromptStageTracker {

    public typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable

    @Published public private(set) var stage: UpdatePromptStage = .none

    private let store: any ThrowingKeyedStoring<UpdateControllerSettings>
    private let settings: () -> MoreProminentUpdatesSettings
    private let installedVersion: String
    private let now: () -> Date
    private let schedule: Scheduler

    private var isUpdateAvailable = false
    private var isCriticalUpdate = false
    private var pendingReevaluation: AnyCancellable?
    private var reevaluationTriggerCancellable: AnyCancellable?

    /// - Parameters:
    ///   - installedVersion: Identifies the running build. Only compared with the value stored when the clock
    ///     started, so any string that changes when the app updates will do. A different value means the user
    ///     updated, so the clock is cleared.
    ///   - reevaluationTriggers: Extra points at which to re-evaluate the stage, besides check results and thresholds.
    public init(store: any ThrowingKeyedStoring<UpdateControllerSettings>,
                settings: @escaping () -> MoreProminentUpdatesSettings,
                installedVersion: String,
                now: @escaping () -> Date = Date.init,
                schedule: @escaping Scheduler = UpdatePromptStageTracker.scheduleOnMainRunLoop,
                reevaluationTriggers: AnyPublisher<Void, Never> = UpdatePromptStageTracker.didBecomeActive) {
        self.store = store
        self.settings = settings
        self.installedVersion = installedVersion
        self.now = now
        self.schedule = schedule

        if storedInstalledVersion != installedVersion {
            clearClock()
        }

        reevaluationTriggerCancellable = reevaluationTriggers.sink { [weak self] in
            DispatchQueue.main.asyncOrNow {
                self?.reevaluate()
            }
        }
    }

    /// The start of the current clock, if one is running.
    public var clockStartDate: Date? {
        try? store.updatePromptClockStartDate
    }

    /// Records the result of an update check. Starts the clock if needed when an update is available, and clears it otherwise.
    public func updateCheckDidFinish(isUpdateAvailable: Bool, isCritical: Bool) {
        self.isUpdateAvailable = isUpdateAvailable
        isCriticalUpdate = isUpdateAvailable && isCritical
        if !isUpdateAvailable {
            clearClock()
        }
        reevaluate()
    }

    public func reevaluate() {
        pendingReevaluation = nil

        guard isUpdateAvailable else {
            stage = .none
            return
        }

        let currentDate = now()
        let startDate: Date
        if let storedStartDate = clockStartDate, storedStartDate <= currentDate {
            startDate = storedStartDate
        } else {
            startDate = currentDate
            startClock(at: currentDate)
        }

        let settings = settings()
        let elapsed = currentDate.timeIntervalSince(startDate)
        stage = isCriticalUpdate ? .secondPrompt : Self.stage(afterElapsed: elapsed, settings: settings)

        guard stage < .secondPrompt else { return }
        let nextThreshold = stage == .available ? settings.firstPromptDelay : settings.secondPromptDelay
        pendingReevaluation = schedule(nextThreshold - elapsed) { [weak self] in
            self?.reevaluate()
        }
    }

    static func stage(afterElapsed elapsed: TimeInterval, settings: MoreProminentUpdatesSettings) -> UpdatePromptStage {
        if elapsed >= settings.secondPromptDelay {
            return .secondPrompt
        } else if elapsed >= settings.firstPromptDelay {
            return .firstPrompt
        } else {
            return .available
        }
    }

    // MARK: - Clock storage

    private var storedInstalledVersion: String? {
        try? store.updatePromptClockInstalledVersion
    }

    private func startClock(at date: Date) {
        try? store.set(date, for: \.updatePromptClockStartDate)
        try? store.set(installedVersion, for: \.updatePromptClockInstalledVersion)
    }

    private func clearClock() {
        try? store.set(nil, for: \.updatePromptClockStartDate)
        try? store.set(nil, for: \.updatePromptClockInstalledVersion)
    }
}

public extension UpdatePromptStageTracker {

    nonisolated static func scheduleOnMainRunLoop(_ delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return AnyCancellable { timer.invalidate() }
    }

    nonisolated static var didBecomeActive: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .map { _ in }
            .eraseToAnyPublisher()
    }
}
