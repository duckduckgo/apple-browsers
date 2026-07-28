//
//  OnboardingView+DuckAIEnabledPersonalizationContent.swift
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
import DesignResourcesKitIcons

extension OnboardingView {

    struct DuckAIEnabledPersonalizationContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding private var isVisible: Bool

        private let content: OnboardingDuckAIEnabledPersonalizationContent
        private let primaryAction: () -> Void
        private let secondaryAction: () -> Void

        init(
            content: OnboardingDuckAIEnabledPersonalizationContent,
            isVisible: Binding<Bool>,
            primaryAction: @escaping () -> Void,
            secondaryAction: @escaping () -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
            self.primaryAction = primaryAction
            self.secondaryAction = secondaryAction
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
                    Text(content.message)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                ),
                showContent: $showContent,
                title: {
                    VStack(alignment: .center, spacing: 16.0) {
                        Image(uiImage: DesignSystemImages.Color.Size96.duckAI)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)

                        TypingText(
                            content.title,
                            startAnimating: $shouldStartTyping,
                            onTypingFinished: { [reduceMotion] in
                                if reduceMotion {
                                    showContent = true
                                } else {
                                    withAnimation { showContent = true }
                                }
                            })
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                    }
                },
                actions: {
                    VStack(spacing: 8) {
                        Button(action: primaryAction) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)

                        Button(action: secondaryAction) {
                            Text(content.secondaryCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

    }
}
