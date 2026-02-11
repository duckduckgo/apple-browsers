//
//  RebrandedOnboardingView+IntroDialogContent.swift
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

private enum IntroDialogContentMetrics {
    static let additionalTopMargin: CGFloat = 40
}

private enum IntroDialogContentCopy {
    static let continueCTA = "Let's do it!"
    static let skipCTA = "I've been here before"
}

extension OnboardingRebranding.OnboardingView {

    struct IntroDialogContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private let title: String
        private let message: String
        private let skipOnboardingView: AnyView?
        private var showCTA: Binding<Bool>
        private let continueAction: () -> Void
        private let skipAction: () -> Void

        @State private var showSkipOnboarding = false

        init(
            title: String,
            message: String,
            skipOnboardingView: AnyView?,
            showCTA: Binding<Bool> = .constant(false),
            continueAction: @escaping () -> Void,
            skipAction: @escaping () -> Void
        ) {
            self.title = title
            self.message = message
            self.skipOnboardingView = skipOnboardingView
            self.showCTA = showCTA
            self.continueAction = continueAction
            self.skipAction = skipAction
        }

        var body: some View {
            if showSkipOnboarding {
                skipOnboardingView
            } else {
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        bubbleContent
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.top, onboardingTheme.linearOnboardingMetrics.minTopMargin + IntroDialogContentMetrics.additionalTopMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear {
                    guard !showCTA.wrappedValue else { return }
                    withAnimation {
                        showCTA.wrappedValue = true
                    }
                }
            }
        }

        private var bubbleContent: some View {
            OnboardingBubbleView(
                tailPosition: .bottom(offset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset, direction: .leading),
                contentInsets: onboardingTheme.linearBubbleMetrics.contentInsets,
                arrowLength: onboardingTheme.linearBubbleMetrics.arrowLength,
                arrowWidth: onboardingTheme.linearBubbleMetrics.arrowWidth
            ) {
                LinearDialogContentContainer(
                    metrics: .init(
                        outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                        textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                        contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                        actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                    ),
                    message: AnyView(
                        Text(message)
                            .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                            .font(onboardingTheme.typography.body)
                            .multilineTextAlignment(.center)
                    ),
                    title: {
                        Text(title)
                            .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                            .font(onboardingTheme.typography.title)
                            .multilineTextAlignment(.center)
                    },
                    actions: {
                        VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                            Button(action: continueAction) {
                                Text(IntroDialogContentCopy.continueCTA)
                            }
                            .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                            if skipOnboardingView != nil {
                                Button(action: {
                                    showSkipOnboarding = true
                                    skipAction()
                                }) {
                                    Text(IntroDialogContentCopy.skipCTA)
                                }
                                .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                            }
                        }
                        .visibility(showCTA.wrappedValue ? .visible : .invisible)
                    }
                )
            }
            .frame(maxWidth: onboardingTheme.linearOnboardingMetrics.bubbleMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }


    }
}
