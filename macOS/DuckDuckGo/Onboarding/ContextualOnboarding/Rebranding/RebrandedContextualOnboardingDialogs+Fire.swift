//
//  RebrandedContextualOnboardingDialogs+Fire.swift
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

// MARK: - Fire Dialog

extension OnboardingRebranding {

    struct OnboardingFireDialog: View {
        let viewModel: OnboardingFireButtonDialogViewModel
        let onManualDismiss: () -> Void
        /// Fires when the bubble transitions in-place to the highFive content,
        /// so the host can swap the background illustration to match.
        let onContentTransition: (() -> Void)?

        @State private var showNextScreen: Bool = false

        var body: some View {
            if showNextScreen {
                OnboardingRebranding.OnboardingEndOfJourneyDialog(
                    highFiveAction: viewModel.highFive,
                    onManualDismiss: onManualDismiss
                )
                .transition(.opacity)
            } else {
                OnboardingBubbleView.withDismissButton(
                    tailPosition: nil,
                    onDismiss: onManualDismiss
                ) {
                    OnboardingFireDialogContent(viewModel: viewModel) {
                        onContentTransition?()
                        withAnimation(.easeInOut(duration: OnboardingRebranding.Layout.inlineTransitionDuration)) {
                            showNextScreen = true
                        }
                    }
                }
                .contextualOnboardingPanelLayout()
                .transition(.opacity)
            }
        }
    }

    struct OnboardingFireDialogContent: View {
        /// Layout values unique to the fire dialog content.
        fileprivate enum Layout {
            /// Vertical spacing between the primary "Try it" button and the skip button.
            static let buttonStackSpacing: CGFloat = 8
            /// Background opacity for the skip button in its normal/pressed states.
            static let skipButtonBackgroundOpacity: Double = 0.12
            static let skipButtonPressedBackgroundOpacity: Double = 0.2
        }

        @Environment(\.onboardingTheme) private var theme

        static let firstString = String(format: UserText.ContextualOnboarding.onboardingTryFireButtonTitle, UserText.ContextualOnboarding.onboardingTryFireButtonMessage)
        private let attributedMessage = NSMutableAttributedString.attributedString(
            from: Self.firstString,
            defaultFontSize: OnboardingDialogsContants.titleFontSize,
            boldFontSize: OnboardingDialogsContants.titleFontSize,
            customPart: UserText.ContextualOnboarding.onboardingTryFireButtonMessage,
            customFontSize: OnboardingDialogsContants.messageFontSize
        )

        let viewModel: OnboardingFireButtonDialogViewModel
        let onSkip: () -> Void

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: .horizontalStack(alignment: .center),
                message: attributedMessage
            ) {
                VStack(spacing: Layout.buttonStackSpacing) {
                    Button(UserText.ContextualOnboarding.onboardingTryFireButtonButton) {
                        viewModel.tryFireButton()
                    }
                    .buttonStyle(theme.primaryButtonStyle.style)

                    Button(UserText.ContextualOnboarding.onboardingTryFireButtonSkip) {
                        viewModel.skipFireButton()
                        onSkip()
                    }
                    .buttonStyle(OnboardingFireDialogSkipButtonStyle())
                }
            }
        }
    }

    private struct OnboardingFireDialogSkipButtonStyle: ButtonStyle {
        @Environment(\.onboardingTheme) private var theme

        func makeBody(configuration: Configuration) -> some View {
            OnboardingRebranding.OnboardingStyles.CTAButtonStyle(
                backgroundColor: Color.secondary.opacity(OnboardingFireDialogContent.Layout.skipButtonBackgroundOpacity),
                pressedBackgroundColor: Color.secondary.opacity(OnboardingFireDialogContent.Layout.skipButtonPressedBackgroundOpacity),
                foregroundColor: theme.colorPalette.textPrimary,
                font: theme.typography.contextual.body
            ).makeBody(configuration: configuration)
        }
    }

}
