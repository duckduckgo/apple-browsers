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
        @State private var showNextScreen: Bool = false
        let initialPanelHeight: CGFloat
        let followUpPanelHeight: CGFloat
        let onManualDismiss: () -> Void

        private var panelHeight: CGFloat {
            showNextScreen ? followUpPanelHeight : initialPanelHeight
        }

        var body: some View {
            OnboardingBubbleView.withDismissButton(
                tailPosition: .leading(offset: 0.3, direction: .top),
                onDismiss: onManualDismiss
            ) {
                if showNextScreen {
                    OnboardingEndOfJourneyDialogContent(highFiveAction: viewModel.highFive)
                } else {
                    OnboardingFireDialogContent(viewModel: viewModel)
                }
            }
            .frame(height: panelHeight, alignment: .top)
        }
    }

    struct OnboardingFireDialogContent: View {
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

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: .horizontalStack(alignment: .center),
                message: attributedMessage
            ) {
                Button(UserText.ContextualOnboarding.onboardingTryFireButtonButton) {
                    viewModel.tryFireButton()
                }
                .buttonStyle(theme.primaryButtonStyle.style)
            }
        }
    }

}
