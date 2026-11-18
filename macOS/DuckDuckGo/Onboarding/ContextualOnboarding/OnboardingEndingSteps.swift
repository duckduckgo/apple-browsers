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

/// The end of contextual onboarding, shared by every path: High Five, then the subscription upsell for eligible users.
/// Methods return `nil` when the ending hasn't started: the decision isn't the ending's to make, and the calling path
/// applies its own rules. That differs from `.none`, which is a decision to show nothing.
final class OnboardingEndingSteps {

    private let progress: ContextualOnboardingProgressReading
    private let subscriptionUpsellExperiment: OnboardingSubscriptionUpsellEnrolling

    init(progress: ContextualOnboardingProgressReading,
         subscriptionUpsellExperiment: OnboardingSubscriptionUpsellEnrolling) {
        self.progress = progress
        self.subscriptionUpsellExperiment = subscriptionUpsellExperiment
    }

    /// Called when a path reaches the end. Enrolls on entering High Five, not on leaving it,
    /// so every exit resolves against the same cohort.
    func start() -> ContextualOnboardingDecision {
        subscriptionUpsellExperiment.enroll()
        return .next(.highFive)
    }

    /// Asked before a path's own rules on every dialog request. Browsing on is the third way out of High Five.
    func decisionForNextDialog() -> ContextualOnboardingDecision? {
        // The upsell shows once; the saved marker also keeps it from returning after a relaunch.
        if progress.hasSeen(.subscriptionUpsell) { return .completed }
        if progress.hasSeen(.highFive) { return afterHighFive() }
        return nil
    }

    /// `nil` when `dialog` isn't part of the ending.
    func gotItPressed(after dialog: ContextualDialogType) -> ContextualOnboardingDecision? {
        switch dialog {
        case .highFive: return afterHighFive()
        case .subscriptionUpsell: return .completed
        default: return nil
        }
    }

    private func afterHighFive() -> ContextualOnboardingDecision {
        subscriptionUpsellExperiment.cohort == .treatment ? .next(.subscriptionUpsell) : .completed
    }
}
