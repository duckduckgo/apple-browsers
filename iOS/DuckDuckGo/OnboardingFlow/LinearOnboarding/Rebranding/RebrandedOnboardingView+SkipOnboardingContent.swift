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
                    Text(Self.styledMessage())
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .font(onboardingTheme.typography.body)
                ),
                title: {
                    Text(UserText.Onboarding.Skip.title)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .font(onboardingTheme.typography.title)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: startBrowsingAction) {
                            Text(UserText.Onboarding.Skip.confirmSkipOnboardingCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: resumeOnboardingAction) {
                            Text(UserText.Onboarding.Skip.resumeOnboardingCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
        }

        /// Builds the message with bold applied to "Fire Button" via SwiftUI's
        /// attribute system so the theme's body font applies uniformly.
        private static func styledMessage() -> AttributedString {
            var attributed = AttributedString(UserText.Onboarding.Skip.message)
            if let range = attributed.range(of: fireButtonCopy) {
                attributed[range].inlinePresentationIntent = .stronglyEmphasized
            }
            return attributed
        }

    }
}
