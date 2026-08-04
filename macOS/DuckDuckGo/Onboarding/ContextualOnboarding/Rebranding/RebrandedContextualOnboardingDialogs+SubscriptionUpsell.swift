//
//  RebrandedContextualOnboardingDialogs+SubscriptionUpsell.swift
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

// MARK: - Subscription Upsell Dialog

extension OnboardingRebranding {

    struct OnboardingSubscriptionUpsellDialog: View {
        /// Layout values unique to the subscription upsell dialog. Shared metrics live on
        /// `OnboardingRebranding.Layout`.
        private enum Layout {
            /// Matches the high-five dialog so the tail doesn't jump between the two screens.
            static let tailOffset: CGFloat = 0.85
            static let arrowLength: CGFloat = 18
            static let arrowWidth: CGFloat = 28
        }

        let acceptAction: () -> Void
        let declineAction: () -> Void
        let onManualDismiss: () -> Void

        var body: some View {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OnboardingBubbleView(
                    tailPosition: .leading(offset: Layout.tailOffset, direction: .top),
                    arrowLength: Layout.arrowLength,
                    arrowWidth: Layout.arrowWidth,
                    content: {
                        OnboardingSubscriptionUpsellDialogContent(acceptAction: acceptAction, declineAction: declineAction)
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

    struct OnboardingSubscriptionUpsellDialogContent: View {
        @Environment(\.onboardingTheme) private var theme

        fileprivate enum Layout {
            /// Figma stacks the two CTAs vertically, primary above secondary.
            static let buttonSpacing: CGFloat = 8
            /// Background opacity for the cancel button in its normal/pressed states.
            static let cancelButtonBackgroundOpacity: Double = 0.12
            static let cancelButtonPressedBackgroundOpacity: Double = 0.2
        }

        let acceptAction: () -> Void
        let declineAction: () -> Void

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: .horizontalStack(alignment: .center),
                title: NSAttributedString(string: UserText.ContextualOnboarding.onboardingSubscriptionUpsellTitle),
                message: NSMutableAttributedString.attributedString(
                    from: UserText.ContextualOnboarding.onboardingSubscriptionUpsellMessage,
                    fontSize: OnboardingDialogsContants.messageFontSize
                )
            ) {
                VStack(spacing: Layout.buttonSpacing) {
                    Button(UserText.ContextualOnboarding.onboardingSubscriptionUpsellAcceptButton) {
                        acceptAction()
                    }
                    .buttonStyle(theme.primaryButtonStyle.style)

                    Button(UserText.ContextualOnboarding.onboardingSubscriptionUpsellDeclineButton) {
                        declineAction()
                    }
                    .buttonStyle(OnboardingSubscriptionUpsellCancelButtonStyle())
                }
            }
        }
    }

    private struct OnboardingSubscriptionUpsellCancelButtonStyle: ButtonStyle {
        @Environment(\.onboardingTheme) private var theme

        func makeBody(configuration: Configuration) -> some View {
            OnboardingRebranding.OnboardingStyles.CTAButtonStyle(
                backgroundColor: Color.secondary.opacity(OnboardingSubscriptionUpsellDialogContent.Layout.cancelButtonBackgroundOpacity),
                pressedBackgroundColor: Color.secondary.opacity(OnboardingSubscriptionUpsellDialogContent.Layout.cancelButtonPressedBackgroundOpacity),
                foregroundColor: theme.colorPalette.textPrimary,
                font: theme.typography.contextual.body
            ).makeBody(configuration: configuration)
        }
    }

}
