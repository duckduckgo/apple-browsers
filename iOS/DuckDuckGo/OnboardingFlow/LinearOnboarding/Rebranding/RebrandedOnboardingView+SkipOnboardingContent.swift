//
//  RebrandedOnboardingView+SkipOnboardingContent.swift
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

    struct SkipOnboardingContent: View {
        private static let fireButtonCopy = "Fire Button"

        typealias Copy = UserText.Onboarding.Skip

        @Environment(\.onboardingTheme) private var onboardingTheme

        private let startBrowsingAction: () -> Void
        private let resumeOnboardingAction: () -> Void

        init(
            startBrowsingAction: @escaping () -> Void,
            resumeOnboardingAction: @escaping () -> Void
        ) {
            self.startBrowsingAction = startBrowsingAction
            self.resumeOnboardingAction = resumeOnboardingAction
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(AttributedString(Copy.message.attributed.withFont(.daxBodyBold(), forText: Self.fireButtonCopy)))
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .font(onboardingTheme.typography.body)
                ),
                title: {
                    Text(Copy.title)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .font(onboardingTheme.typography.title)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: startBrowsingAction) {
                            Text(Copy.confirmSkipOnboardingCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: resumeOnboardingAction) {
                            Text(Copy.resumeOnboardingCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
        }

    }
}
