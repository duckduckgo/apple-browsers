//
//  RebrandedContextualOnboardingDialogs+EndOfJourney.swift
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

// MARK: - End Of Journey Dialog

extension OnboardingRebranding {

    /// https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12206-51627&m=dev
    struct OnboardingEndOfJourneyDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.onboardingTheme) private var theme

        var title = UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenTitle
        let message: String
        let cta: String
        let dismissAction: () -> Void
        let onManualDismiss: () -> Void

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-EndOfJourney-TryWebsite",
            size: CGSize(width: 153, height: 169.67),
            position: .left(bottomPadding: -60, xOffset: -40)
        )

        var body: some View {
            // ZStack(alignment: .top) + maxHeight fills the presenter's available space so that
            // DaxAnimationOverlay's GeometryReader reports the true screen height and can anchor
            // Dax to the real bottom of the screen rather than the bottom of the bubble.
            ZStack(alignment: .top) {
                if !OnboardingBubbleAnimationMetrics.isCompactDevice {
                    DaxAnimationOverlay(animation: Self.daxAnimation, playForward: true, isExiting: false)
                }

                OnboardingBubbleView.withDismissButton(
                    tailPosition: OnboardingBubbleAnimationMetrics.isCompactDevice ? nil : .bottom(offset: 0.2, direction: .leading),
                    onDismiss: onManualDismiss
                ) {
                    OnboardingRebranding.ContextualDaxDialogContent(
                        orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation(horizontalAlignment: .center).build(v: vSizeClass, h: hSizeClass),
                        title: title,
                        message: message
                    ) {
                        Button(action: dismissAction) {
                            Text(cta)
                        }
                        .frame(maxWidth: Metrics.buttonMaxWidth.build(v: vSizeClass, h: hSizeClass))
                        .buttonStyle(theme.primaryButtonStyle.style)
                    }
                }
                .padding(theme.contextualOnboardingMetrics.containerPadding)
                .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

private extension OnboardingRebranding.OnboardingEndOfJourneyDialog {

    enum Metrics {
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).iPhone(landscape: 170.0).iPad(170.0)
    }

}
