//
//  RebrandedOnboardingView+AddToDockContent.swift
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
import UIKit

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoContent: View {

        @State private var showAddToDockTutorial = false
        @State private var animateTitle = true
        @State private var animateMessage = false
        @State private var showContent = false

        private let isAnimating: Binding<Bool>
        private let isSkipped: Binding<Bool>
        private let showTutorialAction: () -> Void
        private let dismissAction: (_ fromAddToDock: Bool) -> Void

        init(
            isAnimating: Binding<Bool> = .constant(true),
            isSkipped: Binding<Bool>,
            showTutorialAction: @escaping () -> Void,
            dismissAction: @escaping (_ fromAddToDock: Bool) -> Void
        ) {
            self.isAnimating = isAnimating
            self.isSkipped = isSkipped
            self.showTutorialAction = showTutorialAction
            self.dismissAction = dismissAction
        }

        var body: some View {
            Group {
                if showAddToDockTutorial {
                    RebrandedOnboardingView.AddToDockTutorialContent(cta: UserText.AddToDockOnboarding.Buttons.gotIt, isSkipped: isSkipped) {
                        dismissAction(true)
                    }
                } else {
                    promoContent
                }
            }
            .onboardingDaxDialogStyle()
        }

        private var promoContent: some View {
            VStack(spacing: 16.0) {
                AnimatableTypingText(UserText.AddToDockOnboarding.Promo.title, startAnimating: $animateTitle, skipAnimation: isSkipped) {
                    withAnimation {
                        animateMessage = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font(UIFont.daxTitle3()))

                AnimatableTypingText(UserText.AddToDockOnboarding.Promo.introMessage, startAnimating: $animateMessage, skipAnimation: isSkipped) {
                    withAnimation {
                        showContent = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 16))

                VStack(spacing: 24) {
                    addToDockPromoView
                    customActionView
                }
                .visibility(showContent ? .visible : .invisible)
            }
        }

        private var addToDockPromoView: some View {
            RebrandedOnboardingView.AddToDockPromoView()
                .aspectRatio(contentMode: .fit)
                .padding(.vertical)
        }

        private var customActionView: some View {
            VStack {
                RebrandedOnboardingView.OnboardingCTAButton(
                    title: UserText.AddToDockOnboarding.Buttons.tutorial,
                    buttonStyle: .primary(compact: false),
                    action: {
                        showTutorialAction()
                        isSkipped.wrappedValue = false
                        showAddToDockTutorial = true
                    }
                )

                RebrandedOnboardingView.OnboardingCTAButton(
                    title: UserText.AddToDockOnboarding.Buttons.skip,
                    buttonStyle: .ghost,
                    action: {
                        dismissAction(false)
                    }
                )
            }
        }

    }

    struct AddToDockTutorialContent: View {
        let title = UserText.AddToDockOnboarding.Tutorial.title
        let message = UserText.AddToDockOnboarding.Tutorial.message

        let cta: String
        let isSkipped: Binding<Bool>
        let dismissAction: () -> Void

        var body: some View {
            RebrandedOnboardingView.AddToDockTutorialView(
                title: title,
                message: message,
                cta: cta,
                isSkipped: isSkipped,
                action: dismissAction
            )
        }
    }

}
