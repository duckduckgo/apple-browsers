//
//  RebrandedContextualOnboardingDialogs+ThatsDuckAI.swift
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

extension OnboardingRebranding {

    /// Shown on Duck.ai after its first answer. It can't be closed, and stays up until Fire is used.
    struct OnboardingThatsDuckAIDialog: View {
        @Environment(\.onboardingTheme) private var theme

        let title = NSAttributedString(string: UserText.ContextualOnboarding.onboardingThatsDuckAITitle)
        let message = NSMutableAttributedString.attributedString(
            from: UserText.ContextualOnboarding.onboardingThatsDuckAIMessage,
            fontSize: OnboardingDialogsContants.messageFontSize
        )
        let onTryIt: @MainActor () -> Void

        var body: some View {
            OnboardingBubbleView(tailPosition: nil) {
                OnboardingRebranding.ContextualDaxDialogContent(
                    orientation: .horizontalStack(alignment: .center),
                    title: title,
                    message: message
                ) {
                    Button(UserText.ContextualOnboarding.onboardingTryFireButtonButton) {
                        onTryIt()
                    }
                    .buttonStyle(theme.primaryButtonStyle.style)
                }
            }
            .contextualOnboardingPanelLayout()
        }
    }
}
