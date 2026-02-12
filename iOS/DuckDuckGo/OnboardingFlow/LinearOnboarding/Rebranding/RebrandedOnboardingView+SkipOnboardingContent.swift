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

import SwiftUI
import DuckUI
import Onboarding

private enum SkipOnboardingContentMetrics {
    static let titleFont = Font.system(size: 20, weight: .bold)
    static let messageFont = Font.system(size: 16)
    static let buttonMaxHeight: CGFloat = 50.0
    static let additionalTopMargin: CGFloat = 0
}

extension OnboardingRebranding.OnboardingView {

    struct SkipOnboardingContent: View {
        private static let fireButtonCopy = "Fire Button"

        typealias Copy = UserText.Onboarding.Skip

        @Environment(\.onboardingTheme) private var onboardingTheme

        private var animateTitle: Binding<Bool>
        private var animateMessage: Binding<Bool>
        private var showCTA: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let startBrowsingAction: () -> Void
        private let resumeOnboardingAction: () -> Void

        init(
            animateTitle: Binding<Bool>,
            animateMessage: Binding<Bool>,
            showCTA: Binding<Bool>,
            isSkipped: Binding<Bool>,
            startBrowsingAction: @escaping () -> Void,
            resumeOnboardingAction: @escaping () -> Void
        ) {
            self.animateTitle = animateTitle
            self.animateMessage = animateMessage
            self.showCTA = showCTA
            self.isSkipped = isSkipped
            self.startBrowsingAction = startBrowsingAction
            self.resumeOnboardingAction = resumeOnboardingAction
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentOuterSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentOuterSpacing,
                    contentSpacing: 0,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    AnimatableTypingText(Copy.message.attributed.withFont(.daxBodyBold(), forText: Self.fireButtonCopy), startAnimating: animateMessage, skipAnimation: isSkipped) {
                        withAnimation {
                            showCTA.wrappedValue = true
                        }
                    }
                    .foregroundColor(.primary)
                    .font(SkipOnboardingContentMetrics.messageFont)
                ),
                title: {
                    AnimatableTypingText(Copy.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                        withAnimation {
                            animateMessage.wrappedValue = true
                        }
                    }
                    .foregroundColor(.primary)
                    .font(SkipOnboardingContentMetrics.titleFont)
                },
                actions: {
                    VStack {
                        Button(action: startBrowsingAction) {
                            Text(Copy.confirmSkipOnboardingCTA)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        OnboardingBorderedButton(
                            maxHeight: SkipOnboardingContentMetrics.buttonMaxHeight,
                            content: {
                                Text(Copy.resumeOnboardingCTA)
                            },
                            action: resumeOnboardingAction
                        )
                    }
                    .visibility(showCTA.wrappedValue ? .visible : .invisible)
                }
            )
        }

    }
}
