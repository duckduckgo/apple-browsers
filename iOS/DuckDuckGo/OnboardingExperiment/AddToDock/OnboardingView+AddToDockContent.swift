//
//  OnboardingView+AddToDockContent.swift
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
import Onboarding

extension OnboardingView {

    struct AddToDockPromoContent: View {

        @State private var showAddToDockTutorial = false

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
            if showAddToDockTutorial {
                OnboardingAddToDockTutorialContent(cta: UserText.AddToDockOnboarding.Buttons.gotIt, isSkipped: isSkipped) {
                    dismissAction(true)
                }
            } else {
                ContextualDaxDialogContent(
                    title: UserText.AddToDockOnboarding.Promo.title,
                    titleFont: Font(UIFont.daxTitle3()),
                    message: NSAttributedString(string: UserText.AddToDockOnboarding.Promo.introMessage),
                    messageFont: Font.system(size: 16),
                    customView: AnyView(addToDockPromoView),
                    customActionView: AnyView(customActionView),
                    skipAnimations: isSkipped
                )
            }
        }

        private var addToDockPromoView: some View {
            AddToDockPromoView()
                .aspectRatio(contentMode: .fit)
                .padding(.vertical)
        }

        private var customActionView: some View {
            VStack {
                OnboardingCTAButton(
                    title: UserText.AddToDockOnboarding.Buttons.tutorial,
                    buttonStyle: .primary(compact: false),
                    action: {
                        showTutorialAction()
                        isSkipped.wrappedValue = false
                        showAddToDockTutorial = true
                    }
                )

                OnboardingCTAButton(
                    title: UserText.AddToDockOnboarding.Buttons.skip,
                    buttonStyle: .ghost,
                    action: {
                        dismissAction(false)
                    }
                )
            }
        }

    }

}
