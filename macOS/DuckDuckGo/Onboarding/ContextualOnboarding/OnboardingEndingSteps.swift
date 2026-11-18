//
//  OnboardingEndingSteps.swift
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

import Foundation
import Persistence

/// What the ending answers when a path asks for the next dialog.
enum OnboardingEndingDecision: Equatable {
    /// High Five hasn't been shown yet, so the path applies its own rules.
    case notStarted
    case decided(ContextualOnboardingDecision)
}

/// What the ending saves, so a relaunch gets the same answer as the session that showed High Five.
protocol OnboardingEndingStoring: AnyObject {
    /// The user's upsell eligibility, saved when High Five starts. `nil` until then, or when it wasn't known yet.
    var subscriptionUpsellEligible: Bool? { get set }
}

struct OnboardingEndingSettings: StoringKeys {
    let subscriptionUpsellEligible = StorageKey<Bool>(.contextualOnboardingSubscriptionUpsellEligible)
}

final class OnboardingEndingStorage: OnboardingEndingStoring {
    private let settings: any KeyedStoring<OnboardingEndingSettings>

    init(settings: any KeyedStoring<OnboardingEndingSettings> = UserDefaults.standard.keyedStoring()) {
        self.settings = settings
    }

    var subscriptionUpsellEligible: Bool? {
        get { settings.subscriptionUpsellEligible }
        set { settings.subscriptionUpsellEligible = newValue }
    }
}

/// The end of contextual onboarding, shared by every path: High Five, then the subscription upsell for eligible users.
final class OnboardingEndingSteps {

    private let progress: ContextualOnboardingProgressReading
    private let storage: OnboardingEndingStoring
    private let subscriptionUpsellEligibility: OnboardingSubscriptionUpsellEligibilityChecking

    init(progress: ContextualOnboardingProgressReading,
         storage: OnboardingEndingStoring,
         subscriptionUpsellEligibility: OnboardingSubscriptionUpsellEligibilityChecking) {
        self.progress = progress
        self.storage = storage
        self.subscriptionUpsellEligibility = subscriptionUpsellEligibility
    }

    /// Called when a path reaches the end. Saves the user's eligibility on entering High Five, so every way out of it,
    /// including after a relaunch, gets the same answer.
    func start() -> ContextualOnboardingDecision {
        if storage.subscriptionUpsellEligible == nil {
            storage.subscriptionUpsellEligible = subscriptionUpsellEligibility.isUserEligible
        }
        return .next(.highFive)
    }

    /// Asked before a path's own rules on every dialog request. Browsing on is the third way out of High Five.
    func decisionForNextDialog() -> OnboardingEndingDecision {
        // The upsell shows once; the saved marker also keeps it from returning after a relaunch.
        if progress.hasSeen(.subscriptionUpsell) { return .decided(.completed) }
        if progress.hasSeen(.highFive) { return .decided(afterHighFive()) }
        return .notStarted
    }

    /// `.none` when `dialog` isn't part of the ending.
    func gotItPressed(after dialog: ContextualDialogType) -> ContextualOnboardingDecision {
        switch dialog {
        case .highFive: return afterHighFive()
        case .subscriptionUpsell: return .completed
        default: return .none
        }
    }

    /// Clears the saved eligibility when onboarding restarts.
    func reset() {
        storage.subscriptionUpsellEligible = nil
    }

    private func afterHighFive() -> ContextualOnboardingDecision {
        guard subscriptionUpsellEligibility.isUpsellEnabled else { return .completed }
        // No saved answer when High Five started before this was saved, or while eligibility was still unknown.
        let isEligible = storage.subscriptionUpsellEligible ?? subscriptionUpsellEligibility.isUserEligible ?? false
        return isEligible ? .next(.subscriptionUpsell) : .completed
    }
}
