//
//  ContextualOnboardingDialogs+EndOfJourneyTryAI.swift
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
import DesignResourcesKitIcons

// MARK: - Search Flow Chat Completion Dialog

extension OnboardingRebranding {

    /// Alternative Search-flow end-of-journey dialog promoting Duck.ai instead of the standard "You've got this!" completion.
    /// Shown only on a NTP
    struct OnboardingEndOfJourneyTryAIDialog: View {

        private enum Metrics {
            static let iconSize = CGSize(width: 96, height: 96)
            static let contentVerticalSpacing: CGFloat = 8
        }

        @Environment(\.onboardingTheme) private var theme

        let title: String
        let message: String
        let primaryCTA: String
        let secondaryCTA: String
        let primaryAction: () -> Void
        let secondaryAction: () -> Void
        /// Suppress the screen-bottom Dax — used by the Duck.ai variant where the
        /// keyboard is up and there's no room for Dax.
        let showsDaxAnimation: Bool

        var body: some View {
            OnboardingBubbleView(tailPosition: nil) {
                VStack {
                    Image(uiImage: DesignSystemImages.Color.Size96.duckAI)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.iconSize.width, height: Metrics.iconSize.height)

                    OnboardingRebranding.ContextualDaxDialogContent(
                        title: title,
                        titleTextAlignment: .center,
                        message: message,
                        messageTextAlignment: .center
                    ) {
                        VStack(spacing: Metrics.contentVerticalSpacing) {
                            Button(action: primaryAction) {
                                Text(primaryCTA)
                            }
                            .buttonStyle(theme.primaryButtonStyle.style)

                            Button(action: secondaryAction) {
                                Text(secondaryCTA)
                            }
                            .buttonStyle(theme.secondaryButtonStyle.style)
                        }
                    }
                }
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            .overlay {
                // Keyboard-aware placement on every non-compact device. Replaces the prior
                // iPhone-only path that left iPad's keyboard covering Dax.
                if showsDaxAnimation && !OnboardingBubbleAnimationMetrics.isCompactDevice {
                    ScreenBottomDaxOverlay(animation: OnboardingRebranding.daxAnimation)
                }
            }
        }
    }

}
