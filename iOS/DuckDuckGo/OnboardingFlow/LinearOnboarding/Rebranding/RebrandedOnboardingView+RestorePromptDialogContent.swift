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

import SwiftUI
import DuckUI
import Onboarding

extension OnboardingRebranding.OnboardingView {

    struct RestorePromptDialogContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private typealias Copy = UserText.Onboarding.RestorePrompt

        private let skipOnboardingView: AnyView?
        private let restoreAction: () -> Void
        private let skipAction: () -> Void

        @State private var showSkipOnboarding = false
        @Binding var showContent: Bool

        init(
            skipOnboardingView: AnyView?,
            showContent: Binding<Bool>,
            restoreAction: @escaping () -> Void,
            skipAction: @escaping () -> Void
        ) {
            self.skipOnboardingView = skipOnboardingView
            self._showContent = showContent
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
                message:
                    AnyView(
                        Text(Copy.body)
                            .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                            .font(onboardingTheme.typography.body)
                            .multilineTextAlignment(.center)
                ),
                title: {
                    Text(Copy.title)
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
        }

        /// Handles the transition from restore dialog to skip onboarding dialog with proper animation timing.
        ///
        /// This function orchestrates a three-phase animation sequence:
        /// 1. Hide current content immediately (no fade-out animation)
        /// 2. Switch to skip dialog and animate bubble resize
        /// 3. Show new content after bubble finishes resizing
        ///
        /// Note: The bubble resize is triggered by the withAnimation wrapping showSkipOnboarding.
        /// Unlike state.type changes which trigger the parent's .animation() modifier, this internal
        /// view switch requires an explicit animation context to smoothly resize the bubble.
        private func showSkipOnboardingDialog() {
            // Phase 1: Hide current content immediately
            showContent = false
            skipAction()

            if #available(iOS 17.0, *) {
                // Phase 2: Animate view switch and bubble resize
                withAnimation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showSkipOnboarding = true
                } completion: {
                    // Phase 3: Show new content after bubble finishes resizing
                    withAnimation {
                        showContent = true
                    }
                }
            } else {
                // Phase 2: Animate view switch and bubble resize
                withAnimation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showSkipOnboarding = true
                }

                // Phase 3: Show new content after bubble finishes resizing (timing-based fallback)
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInDelay) {
                    withAnimation {
                        showContent = true
                    }
                }
            }
        }

    }
}
