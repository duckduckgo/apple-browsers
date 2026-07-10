//
//  RebrandedOnboardingView+IntroDialogContent.swift
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

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12191-31959
    struct IntroDialogContent: View {

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private let content: OnboardingIntroStepContent
        private let skipOnboardingView: AnyView?
        private let continueAction: () -> Void
        private let skipAction: () -> Void
        private let onSkipOnboardingPresented: () -> Void

        @State private var showSkipOnboarding = false
        /// Gates the title's typing animation (waits until the bubble has faded in).
        @State private var shouldStartTyping = false
        /// Fade-in for everything below the title (set after typing completes).
        @State private var showContent = false
        /// Bound to the parent's `showBubbleContent` for hide/show coordination.
        @Binding var isVisible: Bool
        /// Reset before the skip swap so the new `TypingText` doesn't skip itself.
        @Binding var skipTypingAnimation: Bool

        init(
            content: OnboardingIntroStepContent,
            skipOnboardingView: AnyView?,
            isVisible: Binding<Bool>,
            skipTypingAnimation: Binding<Bool>,
            continueAction: @escaping () -> Void,
            skipAction: @escaping () -> Void,
            onSkipOnboardingPresented: @escaping () -> Void
        ) {
            self.content = content
            self.skipOnboardingView = skipOnboardingView
            self._isVisible = isVisible
            self._skipTypingAnimation = skipTypingAnimation
            self.continueAction = continueAction
            self.skipAction = skipAction
            self.onSkipOnboardingPresented = onSkipOnboardingPresented
        }

        var body: some View {
            Group {
                if showSkipOnboarding {
                    skipOnboardingView
                } else {
                    introContent
                }
            }
            .onChange(of: showSkipOnboarding) { newValue in
                if newValue {
                    onSkipOnboardingPresented()
                }
            }
        }

        private var introContent: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
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
                        Button(action: continueAction) {
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
            /* The intro dialog's first appearance scale-fades the bubble in (see the parent's
             `.transition(.scale.combined(with: .opacity))`); the standard typing delay
             (just `contentFadeInAnimationDuration`) lands the typing while the bubble is still
             moving. Add the bubble resize/entrance duration on top so typing only kicks off
             once the bubble is fully settled in its final position.
             */
            .onBubbleVisibilityChanged(
                isVisible: $isVisible,
                shouldStartTyping: $shouldStartTyping,
                showContent: $showContent,
                typingStartDelay: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration
                                + OnboardingBubbleAnimationMetrics.contentFadeInAnimationDuration
            )
        }

        /// Hide → resize → show swap. Deferred so the parent's tap-to-skip gesture fires
        /// before we reset `skipTypingAnimation` and mount the new view.
        private func showSkipOnboardingDialog() {
            isVisible = false
            skipAction()

            // Reduce Motion: jump to final state.
            guard !reduceMotion else {
                skipTypingAnimation = false
                showSkipOnboarding = true
                isVisible = true
                return
            }

            DispatchQueue.main.async {
                skipTypingAnimation = false

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
                    // iOS 16 fallback (no withAnimation completion).
                    DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInDelay) {
                        withAnimation { isVisible = true }
                    }
                }
            }
        }

    }
}
