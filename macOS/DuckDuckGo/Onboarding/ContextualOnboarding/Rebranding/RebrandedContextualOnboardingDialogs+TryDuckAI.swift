//
//  RebrandedContextualOnboardingDialogs+TryDuckAI.swift
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

import SwiftUI
import Onboarding

// MARK: - Try Duck.ai Dialog

extension OnboardingRebranding {

    /// The search path's ending for people who kept Duck.ai in the address bar, in place of High Five.
    struct OnboardingTryDuckAIDialogContent: View {
        /// Vertical spacing between the "Try Duck.ai" and "Skip" buttons, as in the Fire dialog.
        private static let buttonStackSpacing: CGFloat = 8

        @Environment(\.onboardingTheme) private var theme

        let tryDuckAIAction: () -> Void
        let skipAction: () -> Void

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: .horizontalStack(alignment: .center),
                title: NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryDuckAITitle),
                message: NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryDuckAIMessage)
            ) {
                VStack(spacing: Self.buttonStackSpacing) {
                    Button(UserText.ContextualOnboarding.onboardingTryDuckAIButton) {
                        tryDuckAIAction()
                    }
                    .buttonStyle(theme.primaryButtonStyle.style)

                    Button(UserText.ContextualOnboarding.onboardingTryFireButtonSkip) {
                        skipAction()
                    }
                    .buttonStyle(OnboardingSkipButtonStyle())
                }
            }
        }
    }
}
