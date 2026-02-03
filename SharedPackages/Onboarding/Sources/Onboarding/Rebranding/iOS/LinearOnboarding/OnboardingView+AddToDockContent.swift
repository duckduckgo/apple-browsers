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

#if os(iOS)
import SwiftUI
import UIKit
import DesignResourcesKit

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoContent: View {

        @State private var showAddToDockTutorial = false

        private let appIconManager: AppIconProviding
        private let isAnimating: Binding<Bool>
        private let isSkipped: Binding<Bool>
        private let showTutorialAction: () -> Void
        private let dismissAction: (_ fromAddToDock: Bool) -> Void

        init(
            appIconManager: AppIconProviding,
            isAnimating: Binding<Bool> = .constant(true),
            isSkipped: Binding<Bool>,
            showTutorialAction: @escaping () -> Void,
            dismissAction: @escaping (_ fromAddToDock: Bool) -> Void
        ) {
            self.appIconManager = appIconManager
            self.isAnimating = isAnimating
            self.isSkipped = isSkipped
            self.showTutorialAction = showTutorialAction
            self.dismissAction = dismissAction
        }

        var body: some View {
            if showAddToDockTutorial {
                AddToDockTutorialView(
                    title: OnboardingRebranding.UserText.AddToDockOnboarding.Tutorial.title,
                    message: OnboardingRebranding.UserText.AddToDockOnboarding.Tutorial.message,
                    cta: OnboardingRebranding.UserText.AddToDockOnboarding.Buttons.gotIt,
                    isSkipped: isSkipped,
                    action: {
                        dismissAction(true)
                    }
                )
            } else {
                ContextualDaxDialogContent(
                    title: OnboardingRebranding.UserText.AddToDockOnboarding.Promo.title,
                    titleFont: Font(UIFont.daxTitle3()),
                    message: NSAttributedString(string: OnboardingRebranding.UserText.AddToDockOnboarding.Promo.introMessage),
                    messageFont: Font.system(size: 16),
                    customView: AnyView(addToDockPromoView),
                    customActionView: AnyView(customActionView),
                    skipAnimations: isSkipped
                )
            }
        }

        private var addToDockPromoView: some View {
            AddToDockPromoView(appIconManager: appIconManager)
                .aspectRatio(contentMode: .fit)
                .padding(.vertical)
        }

        private var customActionView: some View {
            VStack {
                PrimaryButton(title: OnboardingRebranding.UserText.AddToDockOnboarding.Buttons.tutorial) {
                    showTutorialAction()
                    isSkipped.wrappedValue = false
                    showAddToDockTutorial = true
                }

                SecondaryButton(title: OnboardingRebranding.UserText.AddToDockOnboarding.Buttons.skip) {
                    dismissAction(false)
                }
            }
        }

    }

}
#endif
