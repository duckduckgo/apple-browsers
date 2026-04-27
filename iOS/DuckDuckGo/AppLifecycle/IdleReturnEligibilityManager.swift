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
    /// Is the after-idle feature turned on and ready for this user, regardless
    /// of which treatment (NTP / LUT) their setting selects? Gates everything
    /// — narrow pixel firing, NTP UI, and launch-time evaluation.
    func isFeatureAvailable() -> Bool

    /// Should NTP-specific UI/pixels treat this user as in scope?
    /// Equivalent to `isFeatureAvailable() && effectiveAfterInactivityOption() == .newTab`.
    func isEligibleForNTPAfterIdle() -> Bool

    /// The user's effective After-Inactivity choice (New Tab vs Last Used Tab).
    func effectiveAfterInactivityOption() -> AfterInactivityOption

    /// How many seconds of inactivity before the feature engages.
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

    /// Feature flag on and the user has finished both linear and contextual
    /// onboarding. Independent of which treatment the user picked.
    func isFeatureAvailable() -> Bool {
        tutorialSettings.hasSeenOnboarding
            && !isStillOnboarding()
            && featureFlagger.isFeatureOn(.showNTPAfterIdleReturn)
    }

    func isEligibleForNTPAfterIdle() -> Bool {
        isFeatureAvailable() && effectiveAfterInactivityOption() == .newTab
    }

    func effectiveAfterInactivityOption() -> AfterInactivityOption {
        effectiveOptionResolver.resolveEffectiveOption()
    }

    func idleThresholdSeconds() -> Int {
        thresholdResolver.thresholdSeconds()
    }
}
