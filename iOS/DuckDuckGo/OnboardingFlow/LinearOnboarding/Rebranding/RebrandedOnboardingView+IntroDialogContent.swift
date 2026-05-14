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

        /// Dax "Thumbs Up", sized inversely to the bubble height so the two never overlap.
        /// Returns `nil` when Dax would shrink below `minDaxHeight`. `bubbleHeight = 0`
        /// (no measurement yet) renders Dax at full size so the first frame doesn't blink.
        static func daxAnimation(forBubbleHeight bubbleHeight: CGFloat = 0) -> DaxAnimation? {
            let baseSize = CGSize(width: 258.0, height: 352.0)
            let baseBottomPadding: CGFloat = 110.0
            let baseEntranceXOffset: CGFloat = -20.0
            let baseLargeScreenXOffset: CGFloat = 200.0
            let baseLeftXOffset: CGFloat = -40.0
            /// Threshold above which the bubble starts shrinking Dax 1:1.
            let referenceBubbleHeight: CGFloat = 280.0
            /// Below this height Dax is hidden entirely (per design).
            let minDaxHeight: CGFloat = 170.0

            let extraBubbleHeight = max(0, bubbleHeight - referenceBubbleHeight)
            let targetHeight = baseSize.height - extraBubbleHeight
            guard targetHeight >= minDaxHeight else { return nil }

            let scale = targetHeight / baseSize.height
            let size = CGSize(width: baseSize.width * scale, height: targetHeight)
            // Scale the bottom inset with Dax so the screen-bottom relationship is preserved.
            let bottomPadding = baseBottomPadding * scale

            return DaxAnimation(
                animationName: "Dax-ThumbUp",
                size: size,
                position: .left(bottomPadding: bottomPadding, xOffset: baseLeftXOffset),
                largeScreenPosition: .left(bottomPadding: bottomPadding, xOffset: baseLargeScreenXOffset),
                entranceOffset: CGPoint(x: baseEntranceXOffset, y: 0),
                // Slide left by the full (scaled) width so exit fully clears the screen.
                exitOffset: CGPoint(x: -size.width, y: 0),
                exitDuration: 0.5,
                fadeOut: true,
                startDelay: 0.75
            )
        }

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

        init(
            content: OnboardingIntroStepContent,
            skipOnboardingView: AnyView?,
            isVisible: Binding<Bool>,
            continueAction: @escaping () -> Void,
            skipAction: @escaping () -> Void,
            onSkipOnboardingPresented: @escaping () -> Void
        ) {
            self.content = content
            self.skipOnboardingView = skipOnboardingView
            self._isVisible = isVisible
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

        /// Hide → resize → show transition into the skip dialog. Internal view swap (not a
        /// step change), so we drive the resize explicitly with `withAnimation`.
        private func showSkipOnboardingDialog() {
            isVisible = false
            skipAction()

            // Reduce Motion: jump to the final state, no choreography.
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
