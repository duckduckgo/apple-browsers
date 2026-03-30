//
//  OnboardingView+RestorePromptDialogContent.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

extension OnboardingView {

    struct RestorePromptDialogContent: View {

        typealias Copy = UserText.Onboarding.RestorePrompt

        private let skipOnboardingView: AnyView?
        private var animateText: Binding<Bool>
        private var animateBody: Binding<Bool>
        private var showCTA: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let restoreAction: () -> Void
        private let skipAction: () -> Void

        @State private var showSkipOnboarding = false

        init(
            skipOnboardingView: AnyView? = nil,
            animateText: Binding<Bool> = .constant(true),
            animateBody: Binding<Bool> = .constant(false),
            showCTA: Binding<Bool> = .constant(false),
            isSkipped: Binding<Bool>,
            restoreAction: @escaping () -> Void,
            skipAction: @escaping () -> Void
        ) {
            self.skipOnboardingView = skipOnboardingView
            self.animateText = animateText
            self.animateBody = animateBody
            self.showCTA = showCTA
            self.isSkipped = isSkipped
            self.restoreAction = restoreAction
            self.skipAction = skipAction
        }

        var body: some View {
            if showSkipOnboarding {
                skipOnboardingView
            } else {
                restorePromptContent
            }
        }

        private var restorePromptContent: some View {
            VStack(spacing: 24.0) {
                AnimatableTypingText(Copy.title, startAnimating: animateText, skipAnimation: isSkipped) {
                    withAnimation {
                        animateBody.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 20, weight: .bold))

                AnimatableTypingText(Copy.body, startAnimating: animateBody, skipAnimation: isSkipped) {
                    withAnimation {
                        showCTA.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 16))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                OnboardingActions(
                    viewModel: .init(
                        primaryButtonTitle: Copy.restoreCTA,
                        secondaryButtonTitle: Copy.skipCTA
                    ),
                    primaryAction: restoreAction,
                    secondaryAction: {
                        if skipOnboardingView != nil {
                            isSkipped.wrappedValue = false
                            showSkipOnboarding = true
                        }
                        skipAction()
                    }
                )
                .frame(maxWidth: .infinity)
                .visibility(showCTA.wrappedValue ? .visible : .invisible)
            }
        }
    }
}
