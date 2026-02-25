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

import DuckUI
import Onboarding
import SwiftUI
import UIKit

private enum AddToDockContentMetrics {
    static let messageFont = Font.system(size: 16)
    static let additionalTopMargin: CGFloat = 0
}

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        @State private var showAddToDockTutorial = false
        private let showTutorialAction: () -> Void
        private let dismissAction: (_ fromAddToDock: Bool) -> Void

        init(
            showTutorialAction: @escaping () -> Void,
            dismissAction: @escaping (_ fromAddToDock: Bool) -> Void
        ) {
            self.showTutorialAction = showTutorialAction
            self.dismissAction = dismissAction
        }

        var body: some View {
            if showAddToDockTutorial {
                RebrandedOnboardingView.AddToDockTutorialContent(cta: UserText.AddToDockOnboarding.Buttons.gotIt) {
                    dismissAction(true)
                }
                .onboardingViewVisibleAfterDelay(OnboardingBubbleAnimationMetrics.contentFadeInDelay) // OnboardingViewState does not change in this case so we need to manually fade in the content after bubble resizes.
            } else {
                promoContent
            }
        }

        private var promoContent: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(UserText.AddToDockOnboarding.Promo.introMessage)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                content: AnyView(
                    addToDockPromoView
                ),
                title: {
                    Text(UserText.AddToDockOnboarding.Promo.title)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: {
                            showTutorialAction()
                            withAnimation {
                                showAddToDockTutorial = true
                            }
                        }) { Text(UserText.AddToDockOnboarding.Buttons.tutorial) }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: { dismissAction(false) }) {
                            Text(UserText.AddToDockOnboarding.Buttons.skip)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
        }

        private var addToDockPromoView: some View {
            RebrandedOnboardingView.AddToDockPromoView()
                .aspectRatio(contentMode: .fit)
                .padding(.vertical)
        }
    }

    struct AddToDockTutorialContent: View {
        let title = UserText.AddToDockOnboarding.Tutorial.title
        let message = UserText.AddToDockOnboarding.Tutorial.message

        let cta: String
        let dismissAction: () -> Void

        var body: some View {
            RebrandedOnboardingView.AddToDockTutorialView(
                title: title,
                message: message,
                cta: cta,
                action: dismissAction
            )
        }
    }

}
