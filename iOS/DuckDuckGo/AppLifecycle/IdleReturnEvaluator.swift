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

enum IdleReturnTreatment {
    case ntp
    case lut
}

protocol IdleReturnEvaluating {
    func didReturnAfterIdle(lastBackgroundDate: Date?) -> Bool
    func treatmentForIdleReturn() -> IdleReturnTreatment
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

final class IdleReturnEvaluator: IdleReturnEvaluating {

    private let eligibilityManager: IdleReturnEligibilityManaging

    init(eligibilityManager: IdleReturnEligibilityManaging) {
        self.eligibilityManager = eligibilityManager
    }

    func didReturnAfterIdle(lastBackgroundDate: Date?) -> Bool {
        guard eligibilityManager.isFeatureAvailable(),
              let lastBackgroundDate else {
            return false
        }
        let thresholdSeconds = eligibilityManager.idleThresholdSeconds()
        return Date().timeIntervalSince(lastBackgroundDate) >= Double(thresholdSeconds)
    }

    func treatmentForIdleReturn() -> IdleReturnTreatment {
        switch eligibilityManager.effectiveAfterInactivityOption() {
        case .newTab:
            return .ntp
        case .lastUsedTab:
            return .lut
        }
    }
}
