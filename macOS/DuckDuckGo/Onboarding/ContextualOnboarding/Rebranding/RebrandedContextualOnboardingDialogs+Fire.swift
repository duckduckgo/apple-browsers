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
        @State private var showsTryDuckAI: Bool = false

        var body: some View {
            if showNextScreen {
                if showsTryDuckAI {
                    OnboardingRebranding.OnboardingEndOfJourneyDialog(onManualDismiss: onManualDismiss) {
                        OnboardingRebranding.OnboardingTryDuckAIDialogContent(
                            tryDuckAIAction: viewModel.tryDuckAI,
                            skipAction: viewModel.highFive
                        )
                    }
                    .transition(.opacity)
                } else {
                    OnboardingRebranding.OnboardingEndOfJourneyDialog(
                        highFiveAction: viewModel.highFive,
                        onManualDismiss: onManualDismiss
                    )
                    .transition(.opacity)
                }
            } else {
                OnboardingBubbleView.withDismissButton(
                    tailPosition: nil,
                    onDismiss: onManualDismiss
                ) {
                    OnboardingFireDialogContent(viewModel: viewModel) {
                        // Skip has already moved onboarding to its ending.
                        showsTryDuckAI = viewModel.endsWithTryDuckAI
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
                    .buttonStyle(OnboardingSkipButtonStyle())
                }
            }
        }
    }

    /// The secondary "Skip" button under a dialog's main button.
    struct OnboardingSkipButtonStyle: ButtonStyle {
        /// Background opacity in the normal/pressed states.
        private static let backgroundOpacity: Double = 0.12
        private static let pressedBackgroundOpacity: Double = 0.2

        @Environment(\.onboardingTheme) private var theme

        func makeBody(configuration: Configuration) -> some View {
            OnboardingRebranding.OnboardingStyles.CTAButtonStyle(
                backgroundColor: Color.secondary.opacity(Self.backgroundOpacity),
                pressedBackgroundColor: Color.secondary.opacity(Self.pressedBackgroundOpacity),
                foregroundColor: theme.colorPalette.textPrimary,
                font: theme.typography.contextual.body
            ).makeBody(configuration: configuration)
        }
    }

}
