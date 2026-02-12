//
//  OnboardingView+SkipOnboardingContent.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Onboarding
import DuckUI

extension OnboardingView {

    struct SkipOnboardingContent: View {
        private static let fireButtonCopy = "Fire Button"

        typealias Copy = UserText.Onboarding.Skip

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
            VStack(spacing: 20.0) {
                VStack(spacing: 28.0) {
                    AnimatableTypingText(Copy.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                        withAnimation {
                            animateMessage.wrappedValue = true
                        }
                    }
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .font(Font.system(size: 24, weight: .bold))

                    AnimatableTypingText(Copy.message.attributed.withFont(.daxBodyBold(), forText: Self.fireButtonCopy), startAnimating: animateMessage, skipAnimation: isSkipped) {
                        withAnimation {
                            showCTA.wrappedValue = true
                        }
                    }
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .font(Font.system(size: 18))
                }

                VStack(spacing: 8.0) {
                    Button(action: startBrowsingAction) {
                        Text(Copy.confirmSkipOnboardingCTA)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(action: resumeOnboardingAction) {
                        Text(Copy.resumeOnboardingCTA)
                    }
                    .buttonStyle(SecondaryFillButtonStyle())
                }
                .visibility(showCTA.wrappedValue ? .visible : .invisible)
            }
        }

    }
}
