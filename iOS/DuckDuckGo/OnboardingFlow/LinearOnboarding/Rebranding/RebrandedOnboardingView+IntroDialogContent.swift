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

        /// Dax "Thumbs Up" animation
        static var daxAnimation: DaxAnimation {
            DaxAnimation(
                animationName: "Dax-ThumbUp",
                size: CGSize(width: 258, height: 352),
                position: .left(bottomPadding: 110.0, xOffset: -40.0),
                largeScreenPosition: .left(bottomPadding: 110.0, xOffset: 200.0),
                entranceOffset: CGPoint(x: -100, y: 0),
                exitOffset: CGPoint(x: -258, y: 0),
                exitDuration: 0.5,
                fadeOut: true
            )
        }

        @Environment(\.onboardingTheme) private var onboardingTheme

        private let title: String
        private let message: String
        private let skipOnboardingView: AnyView?
        private let continueAction: () -> Void
        private let skipAction: () -> Void

        @State private var showSkipOnboarding = false
        /// Controls when the TypingText animation begins (delayed until the bubble fade-in finishes).
        @State private var shouldStartTyping = false
        /// Drives the opacity fade-in of everything below the title (set after typing completes).
        @State private var showContent = false
        /// Bound to the parent's `showBubbleContent` -- used to coordinate the hide/show cycle.
        @Binding var isVisible: Bool

        init(
            title: String,
            message: String,
            skipOnboardingView: AnyView?,
            isVisible: Binding<Bool>,
            continueAction: @escaping () -> Void,
            skipAction: @escaping () -> Void
        ) {
            self.title = title
            self.message = message
            self.skipOnboardingView = skipOnboardingView
            self._isVisible = isVisible
            self.continueAction = continueAction
            self.skipAction = skipAction
        }

        var body: some View {
            if showSkipOnboarding {
                skipOnboardingView
            } else {
                content
            }
        }

        private var content: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(message)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                showContent: $showContent,
                title: {
                    TypingText(title, startAnimating: $shouldStartTyping, onTypingFinished: {
                        withAnimation { showContent = true }
                    })
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: continueAction) {
                            Text(UserText.Onboarding.Intro.continueCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        if skipOnboardingView != nil {
                            Button(action: showSkipOnboardingDialog) {
                                Text(UserText.Onboarding.Intro.skipCTA)
                            }
                            .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                        }
                    }
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        /// Runs a three-phase child transition (hide -> resize -> show) to switch to the skip dialog.
        /// Unlike parent-level step changes, this is an internal view switch so we need an explicit
        /// withAnimation to drive the bubble resize.
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
