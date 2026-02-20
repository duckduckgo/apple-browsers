//
//  OnboardingSearchExperienceSettingsResolver.swift
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

import PrivacyConfig

/// Resolves the correct source for AI Chat search input settings during onboarding.
///
/// When the onboarding search experience feature is active and the user has made a choice
/// but Dax Dialogs are still in progress, this resolver returns the user's onboarding choice
/// instead of the actual settings. This allows the Settings UI to reflect the user's intent
/// while the actual activation remains deferred until Dax Dialogs complete.
final class OnboardingSearchExperienceSettingsResolver {
    private let featureFlagger: FeatureFlagger
    private let onboardingProvider: OnboardingSearchExperienceProvider
    private let daxDialogsStatusProvider: ContextualDaxDialogStatusProvider
    
    init(featureFlagger: FeatureFlagger,
         onboardingProvider: OnboardingSearchExperienceProvider,
         daxDialogsStatusProvider: ContextualDaxDialogStatusProvider) {
        self.featureFlagger = featureFlagger
        self.onboardingProvider = onboardingProvider
        self.daxDialogsStatusProvider = daxDialogsStatusProvider
    }
    
    /// Returns true when the onboarding search experience feature is active and the user's choice
    /// should be shown in settings while activation remains deferred (until Dax Dialogs complete).
    var shouldUseDeferredOnboardingChoice: Bool {
        featureFlagger.isFeatureOn(.onboardingSearchExperience) &&
        onboardingProvider.didMakeChoiceDuringOnboarding &&
        !onboardingProvider.didApplyOnboardingChoiceSettings &&
        !daxDialogsStatusProvider.hasSeenOnboarding
    }
    
    /// Returns the current value that should be displayed in Settings.
    /// When in deferred mode, returns the onboarding choice; otherwise returns nil
    /// to indicate the caller should use the actual settings value.
    var deferredValue: Bool? {
        guard shouldUseDeferredOnboardingChoice else { return nil }
        return onboardingProvider.didEnableAIChatSearchInputDuringOnboarding
    }
    
    /// Stores the value if in deferred mode.
    /// - Parameter value: The new value to store
    /// - Returns: true if the value was stored (deferred mode), false otherwise
    @discardableResult
    func storeIfDeferred(_ value: Bool) -> Bool {
        guard shouldUseDeferredOnboardingChoice else { return false }
        guard value != onboardingProvider.didEnableAIChatSearchInputDuringOnboarding else { return false }
        onboardingProvider.storeAIChatSearchInputDuringOnboardingChoice(enable: value)
        return true
    }
}
