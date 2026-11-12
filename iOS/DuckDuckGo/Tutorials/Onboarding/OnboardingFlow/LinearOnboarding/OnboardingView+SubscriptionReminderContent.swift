//
//  OnboardingView+SubscriptionReminderContent.swift
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

    /// Tells users who didn't subscribe from the Try VPN step where to subscribe later.
    struct SubscriptionReminderContent: View {

        private enum Metrics {
            static let illustrationAspectRatio: CGFloat = 318 / 240
            static let illustrationCornerRadius: CGFloat = 8
            static let illustrationSpacing: CGFloat = 28
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding private var isVisible: Bool

        private let content: OnboardingSubscriptionReminderContent
        private let action: () -> Void

        init(
            content: OnboardingSubscriptionReminderContent,
            isVisible: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
            self.action = action
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentOuterSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(content.message)
                        .font(onboardingTheme.typography.body)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                ),
                showContent: $showContent,
                title: {
                    VStack(spacing: Metrics.illustrationSpacing) {
                        illustration

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
                    }
                },
                actions: {
                    Button(action: action) {
                        Text(content.cta)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        /// A looping walkthrough of finding Settings > Subscription.
        private var illustration: some View {
            GeometryReader { geometry in
                if let url = Bundle.main.url(forResource: walkthroughFileName, withExtension: "mp4") {
                    AddToDockVideoPlayer(url: url,
                                         frameSize: geometry.size,
                                         shouldLoopVideo: true,
                                         cornerRadiusRatio: 0)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.illustrationCornerRadius))
                    .id(colorScheme)
                }
            }
            .aspectRatio(Metrics.illustrationAspectRatio, contentMode: .fit)
        }

        private var walkthroughFileName: String {
            colorScheme == .dark ? "SubscriptionReminder-walkthrough-dark" : "SubscriptionReminder-walkthrough-light"
        }

    }

}
