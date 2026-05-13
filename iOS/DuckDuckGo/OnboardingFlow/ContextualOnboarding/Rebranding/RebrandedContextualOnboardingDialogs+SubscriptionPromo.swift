//
//  RebrandedContextualOnboardingDialogs+SubscriptionPromo.swift
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

    /// https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12206-52621&m=dev
    struct OnboardingSubscriptionPromoDialog: View {
        @Environment(\.onboardingTheme) private var theme
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        let title: String
        let message: AttributedString
        let proceedText: String
        let dismissText: String
        let proceedAction: () -> Void
        let dismissAction: () -> Void
        let onManualDismiss: () -> Void

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-FloatingLeft",
            size: CGSize(width: 112, height: 222),
            position: .left(bottomPadding: 18)
        )

        var body: some View {
            ZStack(alignment: .top) {
                if !OnboardingBubbleAnimationMetrics.isCompactDevice {
                    DaxAnimationOverlay(animation: Self.daxAnimation, playForward: true, isExiting: false)
                }

            ScrollView(.vertical, showsIndicators: false) {
                OnboardingBubbleView.withDismissButton(
                    tailPosition: OnboardingBubbleAnimationMetrics.shouldHideBubbleTail(for: dynamicTypeSize) ? nil : .bottom(offset: 0.2, direction: .leading),
                    onDismiss: onManualDismiss
                ) {
                    VStack {
                        OnboardingRebrandingImages.Contextual.promoShield
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                        OnboardingRebranding.ContextualDaxDialogContent(
                            title: AttributedString(title),
                            titleTextAlignment: .center,
                            message: message,
                            messageTextAlignment: .center
                        ) {
                            Button(action: proceedAction) {
                                Text(proceedText)
                            }
                            .buttonStyle(theme.primaryButtonStyle.style)
                        }
                    }
                }
                .padding(theme.contextualOnboardingMetrics.containerPadding)
            }
            .scrollIfNeeded()
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            } // ZStack
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}
