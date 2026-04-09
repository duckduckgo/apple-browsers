//
//  RebrandedOnboardingView+RestorePromptDialogContent.swift
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

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12191-42055
    struct RestorePromptDialogContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private typealias Copy = UserText.Onboarding.RestorePrompt

        private let skipOnboardingView: AnyView?
        private let restoreAction: () -> Void
        private let skipAction: () -> Void

        @State private var showSkipOnboarding = false
        @State private var shouldStartTyping = false
        @Binding var isVisible: Bool

        init(
            skipOnboardingView: AnyView?,
            isVisible: Binding<Bool>,
            restoreAction: @escaping () -> Void,
            skipAction: @escaping () -> Void
        ) {
            self.skipOnboardingView = skipOnboardingView
            self._isVisible = isVisible
            self.restoreAction = restoreAction
            self.skipAction = skipAction
        }

        var body: some View {
            if showSkipOnboarding {
                skipOnboardingView
            } else {
                restorePromptContent
            }
        }

        private var restorePromptContent: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(Copy.body)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                title: {
                    TypingText(Copy.title, startAnimating: $shouldStartTyping)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: restoreAction) {
                            Text(Copy.restoreCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        if skipOnboardingView != nil {
                            Button(action: showSkipOnboardingDialog) {
                                Text(Copy.skipCTA)
                            }
                            .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                        }
                    }
                }
            )
            // Delay typing start until the bubble's fade-in completes; reset on hide.
            .onChange(of: isVisible) { showing in
                if showing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInAnimationDuration) {
                        shouldStartTyping = true
                    }
                } else {
                    shouldStartTyping = false
                }
            }
        }

        /// Runs a three-phase child transition (hide -> resize -> show) to switch to the skip dialog.
        /// Uses explicit withAnimation because this is an internal view switch, not a parent state.type change.
        private func showSkipOnboardingDialog() {
            isVisible = false
            skipAction()

            if #available(iOS 17.0, *) {
                withAnimation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showSkipOnboarding = true
                } completion: {
                    withAnimation { isVisible = true }
                }
            } else {
                withAnimation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showSkipOnboarding = true
                }
                // Timing-based fallback for iOS 16 (no completion handler on withAnimation).
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInDelay) {
                    withAnimation { isVisible = true }
                }
            }
        }

    }
}
