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

final class IdleReturnEvaluator: IdleReturnEvaluating {

    enum IdleReturnEvaluatorConstants {
        static let idleThresholdSecondsSettingKey = "idleThresholdSeconds"
        static let defaultIdleThresholdSeconds = 60 // 1 minute
        static let subfeature: any PrivacySubfeature = iOSBrowserConfigSubfeature.showNTPAfterIdleReturn
    }

    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let debugOverridesStorage: any KeyedStoring<IdleReturnDebugOverridesKeys>

    init(featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         debugOverridesStorage: (any KeyedStoring<IdleReturnDebugOverridesKeys>)? = nil) {
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.debugOverridesStorage = if let debugOverridesStorage { debugOverridesStorage } else { UserDefaults.app.keyedStoring() }
    }

    func shouldShowNTPAfterIdle(lastBackgroundDate: Date?) -> Bool {
        guard featureFlagger.isFeatureOn(.showNTPAfterIdleReturn) else {
            return false
        }
        guard let lastBackgroundDate else {
            return false
        }
        let thresholdSeconds = idleThresholdSeconds()
        return Date().timeIntervalSince(lastBackgroundDate) >= Double(thresholdSeconds)
    }

    private func idleThresholdSeconds() -> Int {
        if let overrideSeconds: Int = debugOverridesStorage.thresholdSecondsOverride, overrideSeconds > 0 {
            return overrideSeconds
        }
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: IdleReturnEvaluatorConstants.subfeature),
              let jsonData = settings.data(using: .utf8) else {
            return IdleReturnEvaluatorConstants.defaultIdleThresholdSeconds
        }
        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let value = settingsDict[IdleReturnEvaluatorConstants.idleThresholdSecondsSettingKey] as? NSNumber,
               value.intValue >= 0 {
                return value.intValue
            }
        } catch {
            Logger.general.debug("Idle return NTP idleThresholdSeconds parse failed: \(error.localizedDescription)")
        }
        return IdleReturnEvaluatorConstants.defaultIdleThresholdSeconds
    }
}
