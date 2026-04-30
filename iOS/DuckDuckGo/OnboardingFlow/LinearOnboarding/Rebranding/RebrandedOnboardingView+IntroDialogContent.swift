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

        /// Dax "Thumbs Up" animation, sized as a function of the dialog bubble's measured height
        /// (captured by the parent and passed in). The bigger the bubble — typically because the
        /// user picked a larger Dynamic Type size or longer copy is being shown — the smaller
        /// Dax becomes, so the two never overlap. Once Dax would shrink below the minimum
        /// `minDaxHeight`, this returns `nil` and the parent suppresses the overlay entirely.
        ///
        /// `bubbleHeight` of `0` means "no measurement yet"; we render Dax at full size in that
        /// case so the very first frame (before the parent has captured the bubble's geometry)
        /// doesn't briefly hide Dax.
        static func daxAnimation(forBubbleHeight bubbleHeight: CGFloat = 0) -> DaxAnimation? {
            let baseSize = CGSize(width: 258.0, height: 352.0)
            let baseBottomPadding: CGFloat = 110.0
            let baseEntranceXOffset: CGFloat = -20.0
            let baseLargeScreenXOffset: CGFloat = 200.0
            let baseLeftXOffset: CGFloat = -40.0
            /// Bubble height at default text size / minimum copy. While the bubble stays at or
            /// below this threshold Dax keeps its full size; growth beyond this shrinks Dax 1:1.
            let referenceBubbleHeight: CGFloat = 280.0
            /// Below this height Dax disappears altogether (per design — at very large Dynamic
            /// Type sizes there's simply not enough vertical space to render anything readable).
            let minDaxHeight: CGFloat = 170.0

            // Each point of bubble growth past the reference height takes one point off Dax,
            // until the minimum is reached.
            let extraBubbleHeight = max(0, bubbleHeight - referenceBubbleHeight)
            let targetHeight = baseSize.height - extraBubbleHeight
            guard targetHeight >= minDaxHeight else { return nil }

            let scale = targetHeight / baseSize.height
            let size = CGSize(width: baseSize.width * scale, height: targetHeight)
            // Lower the bottom inset proportionally so Dax keeps the same visual relationship
            // to the screen bottom as it shrinks.
            let bottomPadding = baseBottomPadding * scale

            return DaxAnimation(
                animationName: "Dax-ThumbUp",
                size: size,
                position: .left(bottomPadding: bottomPadding, xOffset: baseLeftXOffset),
                largeScreenPosition: .left(bottomPadding: bottomPadding, xOffset: baseLargeScreenXOffset),
                entranceOffset: CGPoint(x: baseEntranceXOffset, y: 0),
                // Slide off-screen by exactly the (scaled) animation width so exit fully clears.
                exitOffset: CGPoint(x: -size.width, y: 0),
                exitDuration: 0.5,
                fadeOut: true,
                startDelay: 0.75
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

        /// Runs a three-phase child transition (hide -> resize -> show) to switch to the skip dialog.
        /// Unlike parent-level step changes, this is an internal view switch so we need an explicit
        /// withAnimation to drive the bubble resize.
        private func showSkipOnboardingDialog() {
            isVisible = false
            skipAction()

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
