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

    /// Screen-level wrapper that hosts the Trackers dialog together with its Dax animation.
    ///
    /// The Dax overlay is rendered as a sibling of the dialog (not nested inside it), so its
    /// view extent matches the contextual onboarding background — i.e. the full screen — on
    /// every device class. Nesting the overlay inside the dialog body causes
    /// `OnboardingConditionalCenteredScrollableContainerView`'s `.fixedSize(vertical: true)`
    /// on iPad to collapse the GeometryReader to the bubble's intrinsic height, anchoring Dax
    /// to the bubble bottom instead of the screen bottom.
    struct OnboardingTrackersBlockedDialogScreen: View {
        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let message: AttributedString
        var cta = UserText.Onboarding.ContextualOnboarding.onboardingGotItButton
        let blockedTrackersCTAAction: () -> Void
        let onManualDismiss: (_ isShowingNextScreen: Bool) -> Void

        var body: some View {
            ZStack(alignment: .top) {
                // Sibling of the dialog so the Dax view spans the same area as the background.
                // Hidden when transitioning to the Fire follow-up.
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

        let shouldFollowUp: Bool
        let message: AttributedString
        var cta = UserText.Onboarding.ContextualOnboarding.onboardingGotItButton
        @Binding var showNextScreen: Bool
        let blockedTrackersCTAAction: () -> Void
        let onManualDismiss: (_ isShowingNextScreen: Bool) -> Void

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-WingBottom",
            size: CGSize(width: 390/3, height: 211/3),
            position: .left(),
//            largeScreenPosition: .left(),
            twoStagesAnimation: 0.5
        )

        var body: some View {
            OnboardingBubbleView.withDismissButton(tailPosition: nil, onDismiss: { onManualDismiss(showNextScreen) }
            ) {
                if showNextScreen {
                    OnboardingRebranding.OnboardingFireDialogContent(message: UserText.Onboarding.ContextualOnboarding.onboardingTryFireButtonMessage)
                } else {
                    trackersBlockedContent
                }
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
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
