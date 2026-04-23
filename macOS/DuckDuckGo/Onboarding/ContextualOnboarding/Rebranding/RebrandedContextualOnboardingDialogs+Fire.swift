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
        let panelHeight: CGFloat
        let onManualDismiss: () -> Void

        var body: some View {
            // Fire dialog: plain bubble, no tail and no Dax illustration per the Figma.
            OnboardingBubbleView.withDismissButton(
                tailPosition: nil,
                onDismiss: onManualDismiss
            ) {
                OnboardingFireDialogContent(viewModel: viewModel)
            }
            .contextualOnboardingPanelLayout(height: panelHeight)
        }
    }

    struct OnboardingFireDialogContent: View {
        @Environment(\.onboardingTheme) private var theme

        // The localized title has `\n\n` to separate the headline and the custom message part,
        // which renders as an oversized gap in the compact bubble. Collapse to one newline and
        // add paragraph spacing so the secondary line still reads as a separate sentence.
        static let firstString = String(format: UserText.ContextualOnboarding.onboardingTryFireButtonTitle, UserText.ContextualOnboarding.onboardingTryFireButtonMessage)
            .replacingOccurrences(of: "\n\n", with: "\n")
        private let attributedMessage: NSAttributedString = {
            let base = NSMutableAttributedString.attributedString(
                from: firstString,
                defaultFontSize: OnboardingDialogsContants.titleFontSize,
                boldFontSize: OnboardingDialogsContants.titleFontSize,
                customPart: UserText.ContextualOnboarding.onboardingTryFireButtonMessage,
                customFontSize: OnboardingDialogsContants.messageFontSize
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 8
            base.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: base.length))
            return base
        }()

        let viewModel: OnboardingFireButtonDialogViewModel

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: .horizontalStack(alignment: .center),
                message: attributedMessage
            ) {
                VStack(spacing: 8) {
                    Button(UserText.ContextualOnboarding.onboardingTryFireButtonButton) {
                        viewModel.tryFireButton()
                    }
                    .buttonStyle(theme.primaryButtonStyle.style)

                    Button(UserText.ContextualOnboarding.onboardingTryFireButtonSkip) {
                        viewModel.skipFireButton()
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
                backgroundColor: Color.secondary.opacity(0.12),
                pressedBackgroundColor: Color.secondary.opacity(0.2),
                foregroundColor: theme.colorPalette.textPrimary,
                font: theme.typography.contextual.body
            ).makeBody(configuration: configuration)
        }
    }

}
