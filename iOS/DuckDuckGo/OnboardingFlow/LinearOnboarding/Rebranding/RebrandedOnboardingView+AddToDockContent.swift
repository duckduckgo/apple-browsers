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
import Onboarding
import DesignResourcesKit
import Lottie

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        @State private var showTutorial = false
        private typealias Copy = UserText.AddToDockOnboarding
        private let showTutorialAction: () -> Void
        private let skipAction: (_ fromAddToDock: Bool) -> Void
        private let isSkipped: Binding<Bool>

        /// Desired horizontal padding between the content images and the bubble border.
        /// The bubble's own `contentInsets` are larger (e.g. 20 pt) so the images use negative
        /// horizontal padding to extend past the text content area and land at this distance
        /// from the bubble edge.
        private static let imagePaddingFromBubbleBorder: CGFloat = 9.0
        private static let lottiePaddingFromBubbleBorder: CGFloat = 31.0

        init(
            isSkipped: Binding<Bool>,
            skipAction: @escaping (_ fromAddToDock: Bool) -> Void,
            showTutorialAction: @escaping () -> Void) {
                self.isSkipped = isSkipped

                self.skipAction = skipAction
                self.showTutorialAction = showTutorialAction
            }

        var body: some View {
            if showTutorial {
                tutorialContent
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
                    Text(Copy.Tutorial.message)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                content: AnyView(
                    OnboardingRebrandingImages.AddToDock.promo
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, -3)
                ),
                title: {
                    Text(Copy.Promo.title)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: {
                            showTutorialAction()
                            showTutorial = true
                        }) { Text(Copy.Buttons.tutorial) }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: { skipAction(false) }) {
                            Text(Copy.Buttons.skip)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            )
        }

        private var tutorialContent: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(Copy.Tutorial.message)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                content: AnyView( tutorialContentView ),
                title: {
                    Text(Copy.Tutorial.title)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                },
                actions: {
                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: { skipAction(true) }) { Text(Copy.Buttons.gotIt) }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                    }
                }
            )
        }

        private var tutorialContentView: some View {
            return ZStack(alignment: .center) {
                OnboardingRebrandingImages.AddToDock.tutorial
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, -3)
//                LottieView(
//                    lottieFile: "add-to-dock-promo"
////                        isAnimating: $isAnimating,
////                        animationImageProvider: model,
////                        valueProvider: .init(
////                            provider: ColorValueProvider(model.color),
////                            keypath: AnimationKeypath(keypath: Self.appIconFillKeyPath)
////                        )
//                )
//                //                .onFirstAppear {
//                //                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                //                            isAnimating = true
//                //                        }
//                //                }
            }
        }
    }
}
