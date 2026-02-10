//
//  RebrandedOnboardingView+BrowsersComparisonContent.swift
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

enum BrowsersComparisonContentMetrics {
    static let additionalTopMargin: CGFloat = 0
}

extension OnboardingRebranding.OnboardingView {

    struct BrowsersComparisonContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private let title: String
        private let setAsDefaultBrowserAction: () -> Void
        private let cancelAction: () -> Void
        private var isSkipped: Binding<Bool>

        init(
            title: String, 
            isSkipped: Binding<Bool>,
            setAsDefaultBrowserAction: @escaping () -> Void,
            cancelAction: @escaping () -> Void
        ) {
            self.title = title
            self.isSkipped = isSkipped
            self.setAsDefaultBrowserAction = setAsDefaultBrowserAction
            self.cancelAction = cancelAction
        }

        var body: some View {
            OnboardingBubbleView.withStepProgressIndicator(
                tailPosition: .bottom(offset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset, direction: .leading),
                currentStep: 1,
                totalSteps: 5
            ) {
                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    Text(title)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)

                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                        RebrandedBrowsersComparisonTable()

                        VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                            Button(action: setAsDefaultBrowserAction) {
                                Text(UserText.RebrandedOnboarding.BrowsersComparison.cta)
                            }
                            .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                            Button(action: cancelAction) {
                                Text(UserText.RebrandedOnboarding.skip)
                            }
                            .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                        }
                    }
                }
            }
            .frame(maxWidth: onboardingTheme.linearOnboardingMetrics.bubbleMaxWidth)
        }

    }

}
