//
//  RebrandedOnboardingView+AddToDockContent.swift
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

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12203-26425
    struct AddToDockPromoContent: View {

        static var daxAnimation: DaxAnimation {
            DaxAnimation(
                animationName: "Dax-WingLeft",
                size: CGSize(width: 116, height: 208.33),
                position: .left(bottomPadding: 70.0),
                twoStagesAnimation: 0.5
            )
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var showAddToDockTutorial = false
        @State private var shouldStartTypingTitle = false
        @State private var showContent = false
        @Binding var isVisible: Bool
        private let content: OnboardingAddToDockContent
        private let showTutorialAction: () -> Void
        private let dismissAction: (_ fromAddToDock: Bool) -> Void

        init(
            content: OnboardingAddToDockContent,
            isVisible: Binding<Bool>,
            showTutorialAction: @escaping () -> Void,
            dismissAction: @escaping (_ fromAddToDock: Bool) -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
            self.showTutorialAction = showTutorialAction
            self.dismissAction = dismissAction
        }

        var body: some View {
            if showAddToDockTutorial {
                RebrandedOnboardingView.AddToDockTutorialContent(
                    content: content.tutorialStepContent,
                    isVisible: $isVisible
                ) {
                    dismissAction(true)
                }
            } else {
                promoContent
            }
        }

        private var promoContent: some View {
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
                content: AnyView(
                    RebrandedOnboardingView.AddToDockPromoView()
                        .padding(.vertical)
                ),
                showContent: $showContent,
                title: {
                    TypingText(
                        content.title,
                        startAnimating: $shouldStartTypingTitle,
                        onTypingFinished: { [reduceMotion] in
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
                        Button(action: showTutorial) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: { dismissAction(false) }) {
                            Text(content.secondaryCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTypingTitle, showContent: $showContent)
        }

        /// Hide → resize → show transition into the tutorial. Internal view swap, so we drive
        /// the resize explicitly with `withAnimation`.
        private func showTutorial() {
            isVisible = false
            showTutorialAction()

            // Reduce Motion: jump to the final tutorial state.
            guard !reduceMotion else {
                showAddToDockTutorial = true
                isVisible = true
                return
            }

            if #available(iOS 17.0, *) {
                withAnimation(.easeInOut(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showAddToDockTutorial = true
                } completion: {
                    withAnimation { isVisible = true }
                }
            } else {
                withAnimation(.easeInOut(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showAddToDockTutorial = true
                }
                // Timing-based fallback for iOS 16 (no completion handler on withAnimation).
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInDelay) {
                    withAnimation { isVisible = true }
                }
            }
        }
    }

    /// Thin wrapper that passes the localised tutorial copy to `AddToDockTutorialView`.
    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12203-27033
    struct AddToDockTutorialContent: View {
        @Binding var isVisible: Bool
        let content: OnboardingAddToDockContent.TutorialStepContent
        let dismissAction: () -> Void

        init(content: OnboardingAddToDockContent.TutorialStepContent, isVisible: Binding<Bool>, dismissAction: @escaping () -> Void) {
            self.content = content
            self._isVisible = isVisible
            self.dismissAction = dismissAction
        }

        var body: some View {
            RebrandedOnboardingView.AddToDockTutorialView(
                title: content.title,
                message: content.message,
                isVisible: $isVisible,
                cta: content.primaryCTA,
                action: dismissAction
            )
        }
    }

}
