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
                size: CGSize(width: 174, height: 208.33),
                position: .left(bottomPadding: 70.0),
                twoStagesAnimation: 0.5
            )
        }

        @Environment(\.onboardingTheme) private var onboardingTheme

        @State private var showAddToDockTutorial = false
        @State private var shouldStartTypingTitle = false
        @State private var showContent = false
        @Binding var isVisible: Bool
        private let showTutorialAction: () -> Void
        private let dismissAction: (_ fromAddToDock: Bool) -> Void

        init(
            isVisible: Binding<Bool>,
            showTutorialAction: @escaping () -> Void,
            dismissAction: @escaping (_ fromAddToDock: Bool) -> Void
        ) {
            self._isVisible = isVisible
            self.showTutorialAction = showTutorialAction
            self.dismissAction = dismissAction
        }

        var body: some View {
            if showAddToDockTutorial {
                RebrandedOnboardingView.AddToDockTutorialContent(isVisible: $isVisible,
                                                                 cta: UserText.AddToDockOnboarding.Buttons.gotIt) {
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
                    Text(UserText.AddToDockOnboarding.Promo.introMessage)
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
                    TypingText(UserText.AddToDockOnboarding.Promo.title,
                               startAnimating: $shouldStartTypingTitle,
                               onTypingFinished: {
                                   withAnimation { showContent = true }
                               })
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: showTutorial) {
                            Text(UserText.AddToDockOnboarding.Buttons.tutorial)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: { dismissAction(false) }) {
                            Text(UserText.AddToDockOnboarding.Buttons.skip)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTypingTitle, showContent: $showContent)
        }

        /// Runs a three-phase child transition (hide -> resize -> show) to switch from promo to tutorial.
        /// Uses explicit withAnimation because this is an internal view switch, not a parent state.type change.
        private func showTutorial() {
            isVisible = false
            showTutorialAction()

            if #available(iOS 17.0, *) {
                withAnimation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
                    showAddToDockTutorial = true
                } completion: {
                    withAnimation { isVisible = true }
                }
            } else {
                withAnimation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration)) {
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
        let cta: String
        let dismissAction: () -> Void

        init(isVisible: Binding<Bool>, cta: String, dismissAction: @escaping () -> Void) {
            self._isVisible = isVisible
            self.cta = cta
            self.dismissAction = dismissAction
        }

        var body: some View {
            RebrandedOnboardingView.AddToDockTutorialView(
                title: UserText.AddToDockOnboarding.Tutorial.title,
                message: UserText.AddToDockOnboarding.Tutorial.message,
                isVisible: $isVisible,
                cta: cta,
                action: dismissAction
            )
        }
    }

}
