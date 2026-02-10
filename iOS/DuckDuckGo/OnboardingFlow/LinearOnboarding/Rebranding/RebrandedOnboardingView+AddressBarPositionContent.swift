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

private enum AddressBarPositionContentMetrics {
    static let titleFont = Font.system(size: 20, weight: .semibold)
    static let additionalTopMargin: CGFloat = 0
}

extension OnboardingRebranding.OnboardingView {

    struct AddressBarPositionContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private var animateTitle: Binding<Bool>
        private var showContent: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let action: () -> Void

        init(
            animateTitle: Binding<Bool> = .constant(true),
            showContent: Binding<Bool> = .constant(true),
            isSkipped: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.animateTitle = animateTitle
            self.showContent = showContent
            self.isSkipped = isSkipped
            self.action = action
        }

        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentOuterSpacing) {
                AnimatableTypingText(UserText.Onboarding.AddressBarPosition.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                    showContent.wrappedValue = true
                }
                .foregroundColor(.primary)
                .font(AddressBarPositionContentMetrics.titleFont)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    RebrandedOnboardingView.OnboardingAddressBarPositionPicker()

                    Button(action: action) {
                        Text(verbatim: UserText.Onboarding.AddressBarPosition.cta)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .visibility(showContent.wrappedValue ? .visible : .invisible)
            }
        }
    }

}
