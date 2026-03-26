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
import DuckUI
import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12191-46879
    struct AddressBarPositionContent: View {

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-AddressBar",
            size: CGSize(width: 100, height: 111.3),
            position: .bottom(yOffset: 50.0),
            loop: true
        )

        @Environment(\.onboardingTheme) private var onboardingTheme

        @State private var shouldStartTyping = false
        @Binding private var isVisible: Bool
        private let action: () -> Void

        init(isVisible: Binding<Bool>, action: @escaping () -> Void) {
            self._isVisible = isVisible
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
            .onChange(of: isVisible) { showing in
                if showing {
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
