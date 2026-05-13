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

import DuckUI
import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12191-44303
    struct SkipOnboardingContent: View {
        private static let fireButtonCopy = "Fire Button"
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        /// Drives typing/content reveal off the parent's bubble lifecycle so the animation
        /// doesn't re-fire on background return (which re-fires `onAppear` but not `isVisible`).
        @Binding var isVisible: Bool

        private let content: OnboardingIntroStepContent.SkipFlowStepContent
        private let startBrowsingAction: () -> Void
        private let resumeOnboardingAction: () -> Void

        init(
            content: OnboardingIntroStepContent.SkipFlowStepContent,
            isVisible: Binding<Bool>,
            startBrowsingAction: @escaping () -> Void,
            resumeOnboardingAction: @escaping () -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
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
                    styledMessage()
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .font(onboardingTheme.typography.body)
                ),
                showContent: $showContent,
                title: {
                    TypingText(content.title, startAnimating: $shouldStartTyping, onTypingFinished: { [reduceMotion] in
                        if reduceMotion {
                            showContent = true
                        } else {
                            withAnimation { showContent = true }
                        }
                    })
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .font(onboardingTheme.typography.title)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: startBrowsingAction) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: resumeOnboardingAction) {
                            Text(content.secondaryCTA)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        /// Composes the skip message with bold "Fire Button". Uses `Text` concatenation so the
        /// bold weight inherits from the outer `.font(...)`.
        private func styledMessage() -> Text {
            let highlight = Self.fireButtonCopy
            let parts = content.message.components(separatedBy: highlight)
            guard parts.count == 2 else { return Text(content.message) }
            return Text(parts[0]) + Text(highlight).bold() + Text(parts[1])
        }
    }
}
