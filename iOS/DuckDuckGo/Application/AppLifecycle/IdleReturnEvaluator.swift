//
//  IdleReturnEvaluator.swift
//  DuckDuckGo
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
import Core
import Persistence
import PrivacyConfig
import FeatureFlags_iOS

enum IdleReturnTreatment {
    case ntp
    case lut
}

/// What this return to the foreground amounts to: either it crossed the idle threshold and a
/// treatment applies, or it is an ordinary return. Both carry the time away, so a caller never
/// has to ask a second question to report one.
enum IdleReturnOutcome: Equatable {

    case afterIdle(treatment: IdleReturnTreatment, timeAwayMs: Int?)
    case ordinary(timeAwayMs: Int?)

    var timeAwayMs: Int? {
        switch self {
        case .afterIdle(_, let timeAwayMs), .ordinary(let timeAwayMs):
            return timeAwayMs
        }
    }

}

protocol IdleReturnEvaluating {
    /// Resolves the return from a single read of the last-background date.
    func evaluateReturn() -> IdleReturnOutcome
}

/// Key namespace for idle-return NTP debug overrides (typed storage, no dotted keys).
enum IdleReturnDebugStorageKeys: String, StorageKeyDescribing {
    case idleReturnThresholdSecondsDebugOverride = "idle-return-threshold-seconds-debug-override"
}

/// StoringKeys for idle-return debug overrides.
struct IdleReturnDebugOverridesKeys: StoringKeys {
    let thresholdSecondsOverride = StorageKey<Int>(IdleReturnDebugStorageKeys.idleReturnThresholdSecondsDebugOverride)
}

struct IdleReturnThresholdResolver {

    enum Constants {
        static let idleThresholdSecondsSettingKey = "idleThresholdSeconds"
        static let defaultIdleThresholdSeconds = 1800 // 30 minutes
        static let subfeature: any PrivacySubfeature = iOSBrowserConfigSubfeature.showNTPAfterIdleReturn
    }

    private let debugOverridesStorage: (any KeyedStoring<IdleReturnDebugOverridesKeys>)?
    private let userPreferenceStorage: (any ThrowingKeyedStoring<AfterInactivitySettingKeys>)?
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    /// When `debugOverridesStorage` is nil, defaults to `UserDefaults.app.keyedStoring()`.
    /// `userPreferenceStorage`, when provided, is checked before falling back to the privacy config value.
    init(privacyConfigurationManager: PrivacyConfigurationManaging,
         debugOverridesStorage: (any KeyedStoring<IdleReturnDebugOverridesKeys>)? = nil,
         userPreferenceStorage: (any ThrowingKeyedStoring<AfterInactivitySettingKeys>)? = nil) {
        if let debugOverridesStorage {
            self.debugOverridesStorage = debugOverridesStorage
        } else {
            self.debugOverridesStorage = UserDefaults.app.keyedStoring()
        }
        self.userPreferenceStorage = userPreferenceStorage
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    func thresholdSeconds() -> Int {
        if let overrideSeconds: Int = debugOverridesStorage?.thresholdSecondsOverride, overrideSeconds > 0 {
            return overrideSeconds
        }
        if let userSeconds = try? userPreferenceStorage?.idleReturnIntervalSeconds,
           AfterInactivityIdleInterval(rawValue: userSeconds) != nil {
            return userSeconds
        }
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: Constants.subfeature),
              let jsonData = settings.data(using: .utf8) else {
            return Constants.defaultIdleThresholdSeconds
        }
        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let value = settingsDict[Constants.idleThresholdSecondsSettingKey] as? NSNumber,
               AfterInactivityIdleInterval(rawValue: value.intValue) != nil {
                return value.intValue
            }
        } catch {
            Logger.general.debug("Idle return NTP idleThresholdSeconds parse failed: \(error.localizedDescription)")
        }
        return Constants.defaultIdleThresholdSeconds
    }
}

/// Owns the last-background clock so every caller reads the same value from the same place:
/// the decision, the treatment and the time away all derive from a single read.
final class IdleReturnEvaluator: IdleReturnEvaluating {

    private let eligibilityManager: IdleReturnEligibilityManaging
    private let lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>
    private let now: () -> Date

    init(eligibilityManager: IdleReturnEligibilityManaging,
         lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>,
         now: @escaping () -> Date = Date.init) {
        self.eligibilityManager = eligibilityManager
        self.lastBackgroundDateStorage = lastBackgroundDateStorage
        self.now = now
    }

    func evaluateReturn() -> IdleReturnOutcome {
        let timeAway = timeAwaySinceLastBackground()
        let timeAwayMs = timeAway.map { Int($0 * 1000) }

        guard eligibilityManager.isFeatureAvailable(),
              let timeAway,
              timeAway >= Double(eligibilityManager.idleThresholdSeconds()) else {
            return .ordinary(timeAwayMs: timeAwayMs)
        }
        return .afterIdle(treatment: treatment(), timeAwayMs: timeAwayMs)
    }

    private func timeAwaySinceLastBackground() -> TimeInterval? {
        guard let lastBackgroundDate = (try? lastBackgroundDateStorage.lastBackgroundDate) ?? nil else {
            return nil
        }
        return now().timeIntervalSince(lastBackgroundDate)
    }

    private func treatment() -> IdleReturnTreatment {
        switch eligibilityManager.effectiveAfterInactivityOption() {
        case .newTab:
            return .ntp
        case .lastUsedTab:
            return .lut
        }
    }
}
