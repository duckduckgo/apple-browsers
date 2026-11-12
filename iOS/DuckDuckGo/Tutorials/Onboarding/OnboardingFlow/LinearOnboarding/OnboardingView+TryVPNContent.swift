//
//  OnboardingView+TryVPNContent.swift
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

import DesignResourcesKitIcons
import Onboarding
import SwiftUI

extension OnboardingView {

    /// Figma: https://www.figma.com/design/icdZo7pS4cAWaoVf4byU9t/Add-VPN-to-list-of-download-reasons?node-id=5170-28411
    struct TryVPNContent: View {

        private enum Metrics {
            static let pictogramSize = CGSize(width: 128, height: 96)
            static let headerSpacing: CGFloat = 16
            static let textSpacing: CGFloat = 20
            static let footerTopSpacing: CGFloat = 12
            static let buttonSpacing: CGFloat = 8
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding private var isVisible: Bool

        private let content: OnboardingTryVPNContent
        private let primaryAction: () -> Void
        private let secondaryAction: () -> Void

        init(
            content: OnboardingTryVPNContent,
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
                    outerSpacing: Metrics.textSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    VStack(spacing: Metrics.footerTopSpacing) {
                        Text(content.message)
                            .font(onboardingTheme.typography.body)
                            .foregroundColor(onboardingTheme.colorPalette.textPrimary)

                        Text(content.footer)
                            .font(onboardingTheme.typography.rowDetails)
                            .foregroundColor(onboardingTheme.colorPalette.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                ),
                showContent: $showContent,
                title: {
                    VStack(spacing: Metrics.headerSpacing) {
                        Image(uiImage: DesignSystemImages.Color.Size128.webFeature)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Metrics.pictogramSize.width, height: Metrics.pictogramSize.height)

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
                    VStack(spacing: Metrics.buttonSpacing) {
                        Button(action: primaryAction) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

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
