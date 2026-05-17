//
//  RebrandedOnboardingView+BrowsersComparisonContent.swift
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

import DuckUI
import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=7412-24499
    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=7419-54020
    struct BrowsersComparisonContent: View {

        /// Dax "Wing Wave Up" animation
        static var daxAnimation: DaxAnimation {
            DaxAnimation(
                animationName: "Dax-WingBottom",
                size: CGSize(width: 159.33, height: 180.33),
                position: .bottom(),
                twoStagesAnimation: 0.5,
                exitDuration: 1.0
            )
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @Binding var isVisible: Bool
        @State private var shouldStartTyping = false
        @State private var showContent = false
        private let content: OnboardingBrowserComparisonContent
        private let setAsDefaultBrowserAction: () -> Void
        private let cancelAction: () -> Void

        init(
            content: OnboardingBrowserComparisonContent,
            isVisible: Binding<Bool>,
            setAsDefaultBrowserAction: @escaping () -> Void,
            cancelAction: @escaping () -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
            self.setAsDefaultBrowserAction = setAsDefaultBrowserAction
            self.cancelAction = cancelAction
        }

        // Uses a custom layout instead of LinearDialogContentContainer because
        // the comparison table has its own animated row reveal that needs `showContent`.
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
                        header: .icons(
                            leftIcon: OnboardingRebrandingImages.Comparison.safariIcon,
                            rightIcon: OnboardingRebrandingImages.Comparison.ddgIcon
                        ),
                        features: content.features,
                        availableFeatureAnimation: .animated(startAnimation: showContent)
                    )

                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: setAsDefaultBrowserAction) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: cancelAction) {
                            Text(content.secondaryCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
                .opacity(showContent ? 1 : 0)
                .animation(reduceMotion ? nil : .easeIn(duration: 0.25), value: showContent)
            }
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

    }

}
