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

protocol IdleReturnEvaluating {
    func shouldShowNTPAfterIdle(lastBackgroundDate: Date?) -> Bool
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

    private let debugOverridesStorage: (any KeyedStoring<IdleReturnDebugOverridesKeys>)?
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    /// When `debugOverridesStorage` is nil, defaults to `UserDefaults.app.keyedStoring()`.
    init(privacyConfigurationManager: PrivacyConfigurationManaging,
         debugOverridesStorage: (any KeyedStoring<IdleReturnDebugOverridesKeys>)? = nil) {
        if let debugOverridesStorage {
            self.debugOverridesStorage = debugOverridesStorage
        } else {
            self.debugOverridesStorage = UserDefaults.app.keyedStoring()
        }
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    func thresholdSeconds() -> Int {
        if let overrideSeconds: Int = debugOverridesStorage?.thresholdSecondsOverride, overrideSeconds > 0 {
            return overrideSeconds
        }
        let constants = IdleReturnEvaluator.IdleReturnEvaluatorConstants.self
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: constants.subfeature),
              let jsonData = settings.data(using: .utf8) else {
            return IdleReturnEvaluator.IdleReturnEvaluatorConstants.defaultIdleThresholdSeconds
        }
        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let value = settingsDict[IdleReturnEvaluator.IdleReturnEvaluatorConstants.idleThresholdSecondsSettingKey] as? NSNumber,
               value.intValue >= 0 {
                return value.intValue
            }
        } catch {
            Logger.general.debug("Idle return NTP idleThresholdSeconds parse failed: \(error.localizedDescription)")
        }
        return IdleReturnEvaluator.IdleReturnEvaluatorConstants.defaultIdleThresholdSeconds
    }
}

final class IdleReturnEvaluator: IdleReturnEvaluating {

    enum IdleReturnEvaluatorConstants {
        static let idleThresholdSecondsSettingKey = "idleThresholdSeconds"
        static let defaultIdleThresholdSeconds = 300 // 5 minutes
        static let subfeature: any PrivacySubfeature = iOSBrowserConfigSubfeature.showNTPAfterIdleReturn
    }

    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let debugOverridesStorage: any KeyedStoring<IdleReturnDebugOverridesKeys>
    private let idleReturnEligibilityManager: IdleReturnEligibilityManaging?

    init(featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         debugOverridesStorage: (any KeyedStoring<IdleReturnDebugOverridesKeys>)? = nil,
         idleReturnEligibilityManager: IdleReturnEligibilityManaging? = nil) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.debugOverridesStorage = if let debugOverridesStorage { debugOverridesStorage } else { UserDefaults.app.keyedStoring() }
        self.idleReturnEligibilityManager = idleReturnEligibilityManager
    }

    func shouldShowNTPAfterIdle(lastBackgroundDate: Date?) -> Bool {
        guard featureFlagger.isFeatureOn(.showNTPAfterIdleReturn) else {
            return false
        }
        guard let lastBackgroundDate else {
            return false
        }
        guard idleReturnEligibilityManager?.isEligibleForNTPAfterIdle() ?? true else {
            return false
        }
        let thresholdSeconds = idleThresholdSeconds()
        return Date().timeIntervalSince(lastBackgroundDate) >= Double(thresholdSeconds)
    }

    private func idleThresholdSeconds() -> Int {
        let resolver = IdleReturnThresholdResolver(
            privacyConfigurationManager: privacyConfigurationManager,
            debugOverridesStorage: debugOverridesStorage
        )
        return resolver.thresholdSeconds()
    }
}
