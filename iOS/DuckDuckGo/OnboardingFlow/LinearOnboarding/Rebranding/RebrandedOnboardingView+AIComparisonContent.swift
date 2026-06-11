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
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @Binding var isVisible: Bool
        @State private var shouldStartTyping = false
        @State private var showContent = false

        private let content: OnboardingAIComparisonContent
        private let continueAction: () -> Void

        init(
            content: OnboardingAIComparisonContent,
            isVisible: Binding<Bool>,
            continueAction: @escaping () -> Void,
        ) {
            self.content = content
            self._isVisible = isVisible
            self.continueAction = continueAction
        }

        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
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
                    RebrandedOnboardingComparisonTableView(
                        header: .textAndIcons(
                            title: content.subHeader,
                            leftIcon: OnboardingRebrandingImages.Comparison.popularAIsIcon,
                            rightIcon: OnboardingRebrandingImages.Comparison.ddgIcon
                        ),
                        features: content.features,
                        availableFeatureAnimation: .animated(startAnimation: showContent)
                    )

                    Button(action: continueAction) {
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
