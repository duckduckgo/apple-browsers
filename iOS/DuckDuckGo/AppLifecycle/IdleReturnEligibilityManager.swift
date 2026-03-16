//
//  IdleReturnEligibilityManager.swift
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

protocol IdleReturnEligibilityManaging {
    func isEligibleForNTPAfterIdle() -> Bool
    func effectiveAfterInactivityOption() -> AfterInactivityOption
    func idleThresholdSeconds() -> Int
}

final class IdleReturnEligibilityManager: IdleReturnEligibilityManaging {

    private let featureFlagger: FeatureFlagger
    private let effectiveOptionResolver: AfterInactivityEffectiveOptionResolving
    private let thresholdResolver: IdleReturnThresholdResolver
    private let tutorialSettings: TutorialSettings
    private let isStillOnboarding: () -> Bool

    init(featureFlagger: FeatureFlagger,
         keyValueStore: ThrowingKeyValueStoring,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         debugOverridesStorage: (any KeyedStoring<IdleReturnDebugOverridesKeys>)? = nil,
         tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
         isStillOnboarding: @escaping () -> Bool = { false }) {
        self.featureFlagger = featureFlagger
        self.tutorialSettings = tutorialSettings
        self.isStillOnboarding = isStillOnboarding
        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        self.effectiveOptionResolver = AfterInactivityEffectiveOptionResolver(storage: storage)
        self.thresholdResolver = IdleReturnThresholdResolver(
            privacyConfigurationManager: privacyConfigurationManager,
            debugOverridesStorage: debugOverridesStorage
        )
    }

    init(featureFlagger: FeatureFlagger,
         effectiveOptionResolver: AfterInactivityEffectiveOptionResolving,
         thresholdResolver: IdleReturnThresholdResolver,
         tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
         isStillOnboarding: @escaping () -> Bool = { false }) {
        self.featureFlagger = featureFlagger
        self.effectiveOptionResolver = effectiveOptionResolver
        self.thresholdResolver = thresholdResolver
        self.tutorialSettings = tutorialSettings
        self.isStillOnboarding = isStillOnboarding
    }

    /// Gates NTP-after-idle on linear onboarding completion and contextual
    /// onboarding not actively showing NTP dialogs.
    func isEligibleForNTPAfterIdle() -> Bool {
        tutorialSettings.hasSeenOnboarding
            && !isStillOnboarding()
            && featureFlagger.isFeatureOn(.showNTPAfterIdleReturn)
            && effectiveAfterInactivityOption() == .newTab
    }

    func effectiveAfterInactivityOption() -> AfterInactivityOption {
        effectiveOptionResolver.resolveEffectiveOption()
    }

    func idleThresholdSeconds() -> Int {
        thresholdResolver.thresholdSeconds()
    }
}
