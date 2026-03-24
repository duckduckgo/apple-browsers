//
//  RebrandedOnboardingView+AddressBarPositionContent.swift
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

    struct AddressBarPositionContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        @State private var shouldStartTyping = false
        @Binding private var showContent: Bool
        private let action: () -> Void

        init(showContent: Binding<Bool>, action: @escaping () -> Void) {
            self._showContent = showContent
            self.action = action
        }

        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                TypingText(UserText.Onboarding.AddressBarPosition.title,
                           startAnimating: $shouldStartTyping)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    RebrandedOnboardingView.OnboardingAddressBarPositionPicker()

                    Button(action: action) {
                        Text(verbatim: UserText.Onboarding.AddressBarPosition.cta)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            }
            .onChange(of: showContent) { isVisible in
                if isVisible {
                    DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInAnimationDuration) {
                        shouldStartTyping = true
                    }
                } else {
                    shouldStartTyping = false
                }
            }
        }
    }

}
