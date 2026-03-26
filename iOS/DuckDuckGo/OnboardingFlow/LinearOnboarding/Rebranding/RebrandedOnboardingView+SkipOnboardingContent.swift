//
//  RebrandedOnboardingView+SkipOnboardingContent.swift
//  DuckDuckGo
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

import DuckUI
import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12191-44303
    struct SkipOnboardingContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        @State private var shouldStartTyping = false
        @State private var showContent = false

        private let startBrowsingAction: () -> Void
        private let resumeOnboardingAction: () -> Void

        init(
            startBrowsingAction: @escaping () -> Void,
            resumeOnboardingAction: @escaping () -> Void
        ) {
            self.startBrowsingAction = startBrowsingAction
            self.resumeOnboardingAction = resumeOnboardingAction
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    styledMessage()
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .font(onboardingTheme.typography.body)
                ),
                showContent: $showContent,
                title: {
                    TypingText(UserText.Onboarding.Skip.title, startAnimating: $shouldStartTyping, onTypingFinished: {
                        withAnimation { showContent = true }
                    })
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .font(onboardingTheme.typography.title)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: startBrowsingAction) {
                            Text(UserText.Onboarding.Skip.confirmSkipOnboardingCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: resumeOnboardingAction) {
                            Text(UserText.Onboarding.Skip.resumeOnboardingCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
            // Delay typing start to let the parent bubble resize/fade-in complete;
            // reset on disappear so a second appearance starts fresh.
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInAnimationDuration) {
                    shouldStartTyping = true
                }
            }
            .onDisappear {
                shouldStartTyping = false
                showContent = false
            }
        }

        /// Builds the skip message as a composed Text, bolding the "Fire Button" product name.
        /// Uses Text concatenation so the bold weight inherits from the outer `.font(...)` modifier.
        private func styledMessage() -> Text {
            let message = UserText.Onboarding.Skip.message
            let highlight = UserText.Onboarding.Skip.fireButton
            let parts = message.components(separatedBy: highlight)
            guard parts.count == 2 else { return Text(message) }
            return Text(parts[0]) + Text(highlight).bold() + Text(parts[1])
        }
    }
}
