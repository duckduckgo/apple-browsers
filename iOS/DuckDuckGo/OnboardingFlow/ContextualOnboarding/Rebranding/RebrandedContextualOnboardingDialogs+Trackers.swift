//
//  RebrandedContextualOnboardingDialogs+Trackers.swift
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
import Onboarding
import MetricBuilder

// MARK: - Trackers Blocked

extension OnboardingRebranding {

    /// Screen wrapper that hosts the Trackers dialog plus its Dax. Dax is a sibling (not nested
    /// in the dialog) so it spans the full background — nesting inside the bubble would let
    /// iPad's `.fixedSize` ScrollView anchor Dax to the bubble bottom instead of the screen.
    struct OnboardingTrackersBlockedDialogScreen: View {
        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let message: AttributedString
        var cta = UserText.Onboarding.ContextualOnboarding.onboardingGotItButton
        let blockedTrackersCTAAction: () -> Void
        /// When `nil` the X dismiss button is hidden (e.g. chat-path onboarding).
        let onManualDismiss: ((_ isShowingNextScreen: Bool) -> Void)?

        var body: some View {
            ZStack(alignment: .top) {
                // Sibling overlay; hidden during the Fire follow-up.
                if !OnboardingBubbleAnimationMetrics.isCompactDevice && !showNextScreen {
                    DaxAnimationOverlay(
                        animation: OnboardingTrackersBlockedDialog.daxAnimation,
                        playForward: true,
                        isExiting: false
                    )
                }

                OnboardingConditionalCenteredScrollableContainerView {
                    OnboardingTrackersBlockedDialog(
                        shouldFollowUp: shouldFollowUp,
                        message: message,
                        cta: cta,
                        showNextScreen: $showNextScreen,
                        blockedTrackersCTAAction: blockedTrackersCTAAction,
                        onManualDismiss: onManualDismiss
                    )
                }
            }
        }
    }

    /// https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12205-39034&m=dev
    struct OnboardingTrackersBlockedDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.onboardingTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let shouldFollowUp: Bool
        let message: AttributedString
        var cta = UserText.Onboarding.ContextualOnboarding.onboardingGotItButton
        @Binding var showNextScreen: Bool
        let blockedTrackersCTAAction: () -> Void
        /// When `nil` the X dismiss button is hidden (e.g. chat-path onboarding).
        let onManualDismiss: ((_ isShowingNextScreen: Bool) -> Void)?

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-WingBottom",
            size: CGSize(width: 390/3, height: 211/3),
            position: .left(),
            twoStagesAnimation: 0.5
        )

        var body: some View {
            if let onManualDismiss {
                OnboardingBubbleView.withDismissButton(tailPosition: nil, onDismiss: { onManualDismiss(showNextScreen) }) {
                    bubbleContent
                }
                .padding(theme.contextualOnboardingMetrics.containerPadding)
                .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            } else {
                OnboardingBubbleView(tailPosition: nil) {
                    bubbleContent
                }
                .padding(theme.contextualOnboardingMetrics.containerPadding)
                .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            }
        }

        @ViewBuilder
        private var bubbleContent: some View {
            if showNextScreen {
                OnboardingRebranding.OnboardingFireDialogContent(message: UserText.Onboarding.ContextualOnboarding.onboardingTryFireButtonMessage)
            } else {
                trackersBlockedContent
            }
        }

        private var trackersBlockedContent: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation(horizontalAlignment: .center).build(v: vSizeClass, h: hSizeClass),
                message: message
            ) {
                Button { [reduceMotion] in
                    blockedTrackersCTAAction()
                    if shouldFollowUp {
                        if reduceMotion {
                            showNextScreen = true
                        } else {
                            withAnimation {
                                showNextScreen = true
                            }
                        }
                    }
                } label: {
                    Text(cta)
                }
                .frame(maxWidth: Metrics.buttonMaxWidth.build(v: vSizeClass, h: hSizeClass))
                .buttonStyle(theme.primaryButtonStyle.style)
            }
        }

    }

}

private extension OnboardingRebranding.OnboardingTrackersBlockedDialog {

    enum Metrics {
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).iPhone(landscape: 156.0).iPad(156.0)
    }

}
