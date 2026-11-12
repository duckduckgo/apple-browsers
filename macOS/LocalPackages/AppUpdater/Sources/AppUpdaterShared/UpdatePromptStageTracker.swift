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
import BrowserServicesKit
import Combine
import Common
import ConcurrencyExtensions
import FeatureFlags_macOS
import Foundation
import Persistence
import PrivacyConfig

public enum UpdatePromptMenuStyle: Sendable {
    case row
    case card
}

/// How far along the prompt ramp a user who hasn't updated is.
public enum UpdatePromptStage: Int, Comparable, CaseIterable, Sendable {
    case none
    case available
    case firstPrompt
    case secondPrompt
    case thirdPrompt

    public static func < (lhs: UpdatePromptStage, rhs: UpdatePromptStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether the menu button shows the notification dot. The toolbar button takes over from it at `.thirdPrompt`.
    public var showsNotificationDot: Bool {
        switch self {
        case .none, .available, .thirdPrompt: false
        case .firstPrompt, .secondPrompt: true
        }
    }

    /// The prominent update prompt the menu shows in place of the regular update item, if any.
    public var prominentMenuPrompt: UpdatePromptMenuStyle? {
        switch self {
        case .none, .available, .firstPrompt: nil
        case .secondPrompt: .row
        case .thirdPrompt: .card
        }
    }

    /// Whether the toolbar shows the update button next to the menu button.
    public var showsToolbarButton: Bool {
        switch self {
        case .none, .available, .firstPrompt, .secondPrompt: false
        case .thirdPrompt: true
        }
    }
}

/// Tracks the update prompt stage from a persisted clock that starts at the first check finding a newer version (day 0).
///
/// The clock survives relaunches and newer releases, and is cleared when the installed version changes,
/// when a check no longer finds an update, or while the feature is off. Critical updates go straight to `.thirdPrompt`.
@MainActor
public final class UpdatePromptStageTracker {

    public typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable

    @Published public private(set) var stage: UpdatePromptStage = .none

    private let store: any ThrowingKeyedStoring<UpdateControllerSettings>
    private let settings: () -> MoreProminentUpdatesSettings
    private let installedVersion: String
    private let now: () -> Date
    private let schedule: Scheduler
    private let forcedStage: () -> UpdatePromptStage?
    private let isEnabled: () -> Bool

    private var isUpdateAvailable = false
    private var isCriticalUpdate = false
    private var pendingReevaluation: AnyCancellable?
    private var reevaluationTriggerCancellable: AnyCancellable?

    /// - Parameters:
    ///   - installedVersion: Identifies the running build. Only compared with the value stored when the clock
    ///     started, so any string that changes when the app updates will do. A different value means the user
    ///     updated, so the clock is cleared.
    ///   - forcedStage: A debug override for the stage while an update is available.
    ///   - isEnabled: Whether the feature is on. While it's off, the stage is `.none` and the clock is cleared.
    ///   - reevaluationTriggers: Extra points at which to re-evaluate the stage, besides check results and thresholds.
    public init(store: any ThrowingKeyedStoring<UpdateControllerSettings>,
                settings: @escaping () -> MoreProminentUpdatesSettings,
                installedVersion: String,
                now: @escaping () -> Date = Date.init,
                schedule: @escaping Scheduler = UpdatePromptStageTracker.scheduleOnMainRunLoop,
                forcedStage: @escaping () -> UpdatePromptStage? = { nil },
                isEnabled: @escaping () -> Bool = { true },
                reevaluationTriggers: AnyPublisher<Void, Never> = UpdatePromptStageTracker.didBecomeActive) {
        self.store = store
        self.settings = settings
        self.installedVersion = installedVersion
        self.now = now
        self.schedule = schedule
        self.forcedStage = forcedStage
        self.isEnabled = isEnabled

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

        guard isEnabled() else {
            if clockStartDate != nil {
                clearClock()
            }
            stage = .none
            return
        }

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
        let computedStage = isCriticalUpdate ? .thirdPrompt : Self.stage(afterElapsed: elapsed, settings: settings)
        stage = forcedStage() ?? computedStage

        let nextThreshold: TimeInterval
        switch computedStage {
        case .none, .available: nextThreshold = settings.firstPromptDelay
        case .firstPrompt: nextThreshold = settings.secondPromptDelay
        case .secondPrompt: nextThreshold = settings.thirdPromptDelay
        case .thirdPrompt: return
        }
        pendingReevaluation = schedule(nextThreshold - elapsed) { [weak self] in
            self?.reevaluate()
        }
    }

    static func stage(afterElapsed elapsed: TimeInterval, settings: MoreProminentUpdatesSettings) -> UpdatePromptStage {
        if elapsed >= settings.thirdPromptDelay {
            return .thirdPrompt
        } else if elapsed >= settings.secondPromptDelay {
            return .secondPrompt
        } else if elapsed >= settings.firstPromptDelay {
            return .firstPrompt
        } else {
            return .available
        }
    }

    /// Moves day 0 so that `stage` starts after `timeRemaining`, for testing the prompts without waiting.
    public func moveClock(to stage: UpdatePromptStage, timeRemaining: TimeInterval = 0) {
        let settings = settings()
        let threshold: TimeInterval = switch stage {
        case .none, .available: 0
        case .firstPrompt: settings.firstPromptDelay
        case .secondPrompt: settings.secondPromptDelay
        case .thirdPrompt: settings.thirdPromptDelay
        }
        startClock(at: now() - max(threshold - timeRemaining, 0))
        reevaluate()
    }

    /// Clears the clock, so it starts again from now if an update is available.
    public func resetClock() {
        clearClock()
        reevaluate()
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

    /// The tracker the update controllers use, driven by the `moreProminentUpdates` flag and its remote settings.
    convenience init(store: any ThrowingKeyedStoring<UpdateControllerSettings>,
                     internalUserDecider: InternalUserDecider,
                     featureFlagger: FeatureFlagger,
                     privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.init(
            store: store,
            settings: {
                MoreProminentUpdatesSettings(privacyConfig: privacyConfigurationManager.privacyConfig,
                                             isInternalUser: internalUserDecider.isInternalUser)
            },
            installedVersion: AppVersion().versionAndBuildNumber,
            forcedStage: { internalUserDecider.isInternalUser ? UpdatesDebugSettings().forcedUpdatePromptStage : nil },
            isEnabled: { featureFlagger.isFeatureOn(.moreProminentUpdates) },
            reevaluationTriggers: Self.didBecomeActive
                .merge(with: internalUserDecider.isInternalUserPublisher.map { _ in }, featureFlagger.updatesPublisher)
                .eraseToAnyPublisher()
        )
    }

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
