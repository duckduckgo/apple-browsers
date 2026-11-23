//
//  DuckAIOnboardingPath.swift
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

import AIChat
import Foundation
import Subscription

/// The path for users who send a Duck.ai prompt from the junction:
/// "That's Duck.ai!" on the Duck.ai tab, then the shared ending on the next new tab.
final class DuckAIOnboardingPath: ContextualOnboardingPath {

    private let progress: ContextualOnboardingProgressReading
    private let ending: OnboardingEndingSteps

    init(progress: ContextualOnboardingProgressReading,
         subscriptionManager: any SubscriptionManager) {
        self.progress = progress
        self.ending = OnboardingEndingSteps(progress: progress, subscriptionManager: subscriptionManager)
    }

    /// Only Fire is allowed until the chat is deleted.
    var uiLock: UserInteractionLock {
        progress.fireButtonUsedOnce ? .unlocked : .locked(except: [.fire])
    }

    func dialog(for tab: Tab) -> ContextualOnboardingDecision {
        if case .decided(let decision) = ending.decisionForNextDialog() { return decision }
        if !progress.hasSeen(.thatsDuckAI) {
            return tab.url?.isDuckAIURL == true ? .next(.thatsDuckAI) : .none
        }
        // The UI stays locked until Fire, so the next page loading means the chat was deleted.
        return ending.start()
    }

    func gotItPressed(lastDialog: ContextualDialogType) -> ContextualOnboardingDecision {
        ending.gotItPressed(after: lastDialog)
    }

    func reset() {}
}
