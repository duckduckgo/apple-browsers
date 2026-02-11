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

private enum BrowsersComparisonContentCopy {
    static let setAsDefaultBrowserCTA = "Choose Your Browser"
    static let skipCTA = "Skip"
}

extension OnboardingRebranding.OnboardingView {

    struct BrowsersComparisonContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private let title: String
        private let currentStep: Int
        private let totalSteps: Int
        private let setAsDefaultBrowserAction: () -> Void
        private let cancelAction: () -> Void

        init(
            title: String,
            currentStep: Int,
            totalSteps: Int,
            setAsDefaultBrowserAction: @escaping () -> Void,
            cancelAction: @escaping () -> Void
        ) {
            self.title = title
            self.currentStep = currentStep
            self.totalSteps = totalSteps
            self.setAsDefaultBrowserAction = setAsDefaultBrowserAction
            self.cancelAction = cancelAction
        }

        var body: some View {
            OnboardingBubbleView.withStepProgressIndicator(
                tailPosition: .bottom(offset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset, direction: .leading),
                currentStep: currentStep,
                totalSteps: totalSteps
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
                                Text(BrowsersComparisonContentCopy.setAsDefaultBrowserCTA)
                            }
                            .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                            Button(action: cancelAction) {
                                Text(BrowsersComparisonContentCopy.skipCTA)
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
