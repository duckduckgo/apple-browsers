//
//  RebrandedOnboardingView+AIComparisonContent.swift
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
import DuckUI
import Onboarding

extension OnboardingRebranding.OnboardingView {

    struct AIComparisonContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        @Binding var showContent: Bool
        private let content: OnboardingAIComparisonContent
        private let continueAction: () -> Void

        init(
            content: OnboardingAIComparisonContent,
            showContent: Binding<Bool>,
            continueAction: @escaping () -> Void,
        ) {
            self.content = content
            self._showContent = showContent
            self.continueAction = continueAction
        }

        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                Text(content.title)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundStyle(Color.blue)
                        .frame(height: 300)

                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: continueAction) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                    }
                }
            }
        }

    }

}
