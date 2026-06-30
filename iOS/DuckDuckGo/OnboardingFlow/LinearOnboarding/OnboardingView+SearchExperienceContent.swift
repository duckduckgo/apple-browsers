//
//  OnboardingView+SearchExperienceContent.swift
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

import Onboarding
import SwiftUI

extension OnboardingView {

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12192-50600
    struct SearchExperienceContent: View {

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding private var isVisible: Bool
        private let content: OnboardingSearchExperienceContent
        private let action: () -> Void

        @StateObject private var viewModel = OnboardingSearchExperiencePickerViewModel()

        init(
            content: OnboardingSearchExperienceContent,
            isVisible: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
            self.action = action
        }

        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentOuterSpacing) {
                TypingText(
                    content.title,
                    startAnimating: $shouldStartTyping,
                    onTypingFinished: { [reduceMotion] in
                        if reduceMotion {
                            showContent = true
                        } else {
                            withAnimation { showContent = true }
                        }
                    }
                )
                .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                .font(onboardingTheme.typography.title)
                .multilineTextAlignment(.center)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    OnboardingView.OnboardingSearchExperiencePicker(isDuckAISelected: viewModel.isSearchAndAIChatEnabled)

                    Text(content.footer)
                        .foregroundColor(onboardingTheme.colorPalette.textSecondary)
                        .font(onboardingTheme.typography.small)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: {
                        viewModel.confirmChoice()
                        action()
                    }) {
                        Text(content.primaryCTA)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
                .opacity(showContent ? 1 : 0)
                .animation(reduceMotion ? nil : .easeIn(duration: 0.25), value: showContent)
            }
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }
    }

}
