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
import Subscription

/// What the ending answers when a path asks for the next dialog.
enum OnboardingEndingDecision: Equatable {
    /// High Five hasn't been shown yet, so the path applies its own rules.
    case notStarted
    case decided(ContextualOnboardingDecision)
}

/// The end of contextual onboarding, shared by every path: High Five, then the subscription upsell for eligible users.
final class OnboardingEndingSteps {

    private let progress: ContextualOnboardingProgressReading
    private let subscriptionManager: any SubscriptionManager

    init(progress: ContextualOnboardingProgressReading,
         subscriptionManager: any SubscriptionManager) {
        self.progress = progress
        self.subscriptionManager = subscriptionManager
    }

    /// Called when a path reaches the end.
    func start() -> ContextualOnboardingDecision {
        .next(.highFive)
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

    private func afterHighFive() -> ContextualOnboardingDecision {
        subscriptionManager.isSubscriptionPurchaseEligible && !subscriptionManager.isUserAuthenticated
            ? .next(.subscriptionUpsell) : .completed
    }
}
