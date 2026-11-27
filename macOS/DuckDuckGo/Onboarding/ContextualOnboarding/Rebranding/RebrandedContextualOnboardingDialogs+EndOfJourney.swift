//
//  RebrandedContextualOnboardingDialogs+EndOfJourney.swift
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

// MARK: - End Of Journey Dialog

/// Layout values unique to the end-of-journey dialogs. Shared metrics live on
/// `OnboardingRebranding.Layout`.
private enum EndOfJourneyLayout {
    /// Bubble tail anchor — pushed further down the leading edge so the tip lands
    /// next to Dax's mouth area rather than near the top of the bubble.
    static let tailOffset: CGFloat = 0.85
    /// Locally smaller tail than the shared `OnboardingRebranding.Layout.bubbleArrow*`
    /// metrics so the high-five bubble's arrow doesn't dominate the tighter layout.
    static let arrowLength: CGFloat = 18
    static let arrowWidth: CGFloat = 28
}

extension OnboardingRebranding {

    /// The last dialog of onboarding, with waving Dax: High Five, or Try Duck.ai.
    struct OnboardingEndOfJourneyDialog<Content: View>: View {
        let onManualDismiss: () -> Void
        let content: Content

        init(onManualDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
            self.onManualDismiss = onManualDismiss
            self.content = content()
        }

        var body: some View {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OnboardingBubbleView(
                    tailPosition: .leading(offset: EndOfJourneyLayout.tailOffset, direction: .top),
                    arrowLength: EndOfJourneyLayout.arrowLength,
                    arrowWidth: EndOfJourneyLayout.arrowWidth,
                    content: {
                        content
                    }
                )
                .onboardingDismissable(onManualDismiss)
                .frame(maxWidth: OnboardingRebranding.Layout.bubbleMaxWidth)
                .overlay(
                    DaxWavingAnimation()
                        .frame(
                            width: OnboardingRebranding.Layout.DaxWaving.width,
                            height: OnboardingRebranding.Layout.DaxWaving.height
                        )
                        .clipped()
                        .offset(
                            x: OnboardingRebranding.Layout.DaxWaving.offsetX,
                            y: OnboardingRebranding.Layout.DaxWaving.offsetY
                        )
                        .allowsHitTesting(false),
                    alignment: .topLeading
                )
                Spacer(minLength: 0)
            }
            .padding(.top, OnboardingRebranding.Layout.panelTopPadding)
            .padding(.bottom, OnboardingRebranding.Layout.panelBottomPadding)
            .frame(maxWidth: .infinity)
        }
    }

    struct OnboardingEndOfJourneyDialogContent: View {
        @Environment(\.onboardingTheme) private var theme

        let title = NSAttributedString(string: UserText.ContextualOnboarding.onboardingFinalScreenTitle)
        let message = NSAttributedString(string: UserText.ContextualOnboarding.onboardingFinalScreenMessage)
        let cta = UserText.ContextualOnboarding.onboardingFinalScreenButton
        let highFiveAction: () -> Void

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: .horizontalStack(alignment: .center),
                title: title,
                message: message
            ) {
                Button(cta) {
                    highFiveAction()
                }
                .buttonStyle(theme.primaryButtonStyle.style)
            }
        }
    }

}

extension OnboardingRebranding.OnboardingEndOfJourneyDialog where Content == OnboardingRebranding.OnboardingEndOfJourneyDialogContent {

    /// High Five.
    init(highFiveAction: @escaping () -> Void, onManualDismiss: @escaping () -> Void) {
        self.init(onManualDismiss: onManualDismiss) {
            OnboardingRebranding.OnboardingEndOfJourneyDialogContent(highFiveAction: highFiveAction)
        }
    }
}
