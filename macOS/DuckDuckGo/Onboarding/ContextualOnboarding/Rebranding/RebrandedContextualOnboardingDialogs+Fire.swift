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
        let onManualDismiss: () -> Void

        var body: some View {
            DaxDialogView(logoPosition: .left, onManualDismiss: onManualDismiss) {
                if showNextScreen {
                    OnboardingEndOfJourneyDialogContent(highFiveAction: viewModel.highFive)
                } else {
                    OnboardingFireDialogContent(viewModel: viewModel)
                }
            }
            .padding()
        }
    }

    struct OnboardingFireDialogContent: View {
        static let firstString = String(format: UserText.ContextualOnboarding.onboardingTryFireButtonTitle, UserText.ContextualOnboarding.onboardingTryFireButtonMessage)
        private let attributedMessage = NSMutableAttributedString.attributedString(
            from: Self.firstString,
            defaultFontSize: OnboardingDialogsContants.titleFontSize,
            boldFontSize: OnboardingDialogsContants.titleFontSize,
            customPart: UserText.ContextualOnboarding.onboardingTryFireButtonMessage,
            customFontSize: OnboardingDialogsContants.messageFontSize
        )

        let viewModel: OnboardingFireButtonDialogViewModel
        @State private var showNextScreen: Bool = false

        var body: some View {
            if showNextScreen {
                OnboardingEndOfJourneyDialogContent(highFiveAction: viewModel.highFive)
            } else {
                Onboarding.ContextualDaxDialogContent(
                    orientation: .horizontalStack(alignment: .center),
                    message: attributedMessage,
                    messageFont: OnboardingDialogsContants.titleFontNotBold,
                    customActionView: AnyView(actionView))
            }
        }

        @ViewBuilder
        private var actionView: some View {
            VStack {
                OnboardingPrimaryCTAButton(title: UserText.ContextualOnboarding.onboardingTryFireButtonButton, action: viewModel.tryFireButton)
            }
        }
    }

}
