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

    struct OnboardingSubscriptionPromoDialog: View {
        @Environment(\.onboardingTheme) private var theme

        let title: String
        let message: AttributedString
        let proceedText: String
        let dismissText: String
        let proceedAction: () -> Void
        let dismissAction: () -> Void
        let onManualDismiss: () -> Void

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                OnboardingBubbleView.withDismissButton(
                    tailPosition: nil,
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
                            VStack(spacing: 8) {
                                Button(action: proceedAction) {
                                    Text(proceedText)
                                }
                                .buttonStyle(theme.primaryButtonStyle.style)

                                Button(action: dismissAction) {
                                    Text(dismissText)
                                }
                                .buttonStyle(theme.secondaryButtonStyle.style)
                            }
                        }
                    }
                }
                .padding(theme.contextualOnboardingMetrics.containerPadding)
            }
            .scrollIfNeeded()
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
        }
    }

}
