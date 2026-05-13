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
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private let content: OnboardingIntroStepContent.RestorePromptStepContent
        private let skipOnboardingView: AnyView?
        private let restoreAction: () -> Void
        private let skipAction: () -> Void
        private let onSkipOnboardingPresented: () -> Void

        @State private var showSkipOnboarding = false
        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding var isVisible: Bool

        init(
            content: OnboardingIntroStepContent.RestorePromptStepContent,
            skipOnboardingView: AnyView?,
            isVisible: Binding<Bool>,
            restoreAction: @escaping () -> Void,
            skipAction: @escaping () -> Void,
            onSkipOnboardingPresented: @escaping () -> Void
        ) {
            self.content = content
            self.skipOnboardingView = skipOnboardingView
            self._isVisible = isVisible
            self.restoreAction = restoreAction
            self.skipAction = skipAction
            self.onSkipOnboardingPresented = onSkipOnboardingPresented
        }

        var body: some View {
            Group {
                if showSkipOnboarding {
                    skipOnboardingView
                } else {
                    restorePromptContent
                }
            }
            .onChange(of: showSkipOnboarding) { newValue in
                if newValue {
                    onSkipOnboardingPresented()
                }
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
                message:
                    AnyView(
                        Text(content.message)
                            .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                            .font(onboardingTheme.typography.body)
                            .multilineTextAlignment(.center)
                ),
                showContent: $showContent,
                title: {
                    TypingText(content.title, startAnimating: $shouldStartTyping, onTypingFinished: { [reduceMotion] in
                        if reduceMotion {
                            showContent = true
                        } else {
                            withAnimation { showContent = true }
                        }
                    })
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: restoreAction) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        if skipOnboardingView != nil {
                            Button(action: showSkipOnboardingDialog) {
                                Text(content.secondaryCTA)
                            }
                            .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                        }
                    }
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        /// Hide → resize → show transition into the skip dialog. Internal view swap, so we drive
        /// the resize explicitly with `withAnimation`.
        private func showSkipOnboardingDialog() {
            isVisible = false
            skipAction()

            // Reduce Motion: jump to the final state.
            guard !reduceMotion else {
                showSkipOnboarding = true
                isVisible = true
                return
            }

            if #available(iOS 17.0, *) {
                withAnimation(.easeInOut(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showSkipOnboarding = true
                } completion: {
                    withAnimation { isVisible = true }
                }
            } else {
                withAnimation(.easeInOut(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
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
