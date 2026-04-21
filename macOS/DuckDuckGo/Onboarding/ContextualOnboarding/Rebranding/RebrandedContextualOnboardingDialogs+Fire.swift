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
            OnboardingBubbleView.withDismissButton(
                tailPosition: .leading(offset: 0.3, direction: .top),
                onDismiss: onManualDismiss
            ) {
                OnboardingFireDialogContent(viewModel: viewModel)
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
