//
//  RebrandedOnboardingView+SearchExperienceContent.swift
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

extension OnboardingRebranding.OnboardingView {

    struct SearchExperienceContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private let action: () -> Void

        @StateObject private var viewModel = OnboardingSearchExperiencePickerViewModel()

        init(action: @escaping () -> Void) {
            self.action = action
        }

        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentOuterSpacing) {
                Text(UserText.Onboarding.SearchExperience.title)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    RebrandedOnboardingView.OnboardingSearchExperiencePicker(viewModel: viewModel)

                    Text(AttributedString(UserText.Onboarding.SearchExperience.footerAttributed()))
                        .foregroundColor(onboardingTheme.colorPalette.textSecondary)
                        .font(onboardingTheme.typography.small)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: {
                        viewModel.confirmChoice()
                        action()
                    }) {
                        Text(UserText.Onboarding.SearchExperience.cta)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            }
        }
    }

}
