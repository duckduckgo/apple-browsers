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

    /// https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12205-39034&m=dev
    struct OnboardingTrackersBlockedDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.onboardingTheme) private var theme

        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let message: AttributedString
        var cta = UserText.Onboarding.ContextualOnboarding.onboardingGotItButton
        let blockedTrackersCTAAction: () -> Void
        let onManualDismiss: (_ isShowingNextScreen: Bool) -> Void

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-WingBottom",
            size: CGSize(width: 390/3, height: 211/3),
            position: .bottom(leftCenterOffset: 150, yOffset: -10.0),
            twoStagesAnimation: 0.5
        )

        var body: some View {
            ZStack(alignment: .top) {
                // Dax is only shown on the trackers screen; hidden when transitioning to the Fire follow-up.
                if !OnboardingBubbleAnimationMetrics.isCompactDevice && !showNextScreen {
                    DaxAnimationOverlay(animation: Self.daxAnimation, playForward: true, isExiting: false)
                }

                OnboardingBubbleView.withDismissButton(tailPosition: nil, onDismiss: { onManualDismiss(showNextScreen) }
                ) {
                    if showNextScreen {
                        OnboardingRebranding.OnboardingFireDialogContent()
                    } else {
                        trackersBlockedContent
                    }
                }
                .padding(theme.contextualOnboardingMetrics.containerPadding)
                .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private var trackersBlockedContent: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation(horizontalAlignment: .center).build(v: vSizeClass, h: hSizeClass),
                message: message
            ) {
                Button {
                    blockedTrackersCTAAction()
                    if shouldFollowUp {
                        withAnimation {
                            showNextScreen = true
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
