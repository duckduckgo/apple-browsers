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
import Core
import DesignResourcesKit
import Lottie

private enum AddToDockContentMetrics {
    static let messageFont = Font.system(size: 16)
    static let additionalTopMargin: CGFloat = 0
}

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        @State private var showTutorial = false
        private typealias Copy = UserText.AddToDockOnboarding
        private let showTutorialAction: () -> Void
        private let skipAction: (_ fromAddToDock: Bool) -> Void
        private let isSkipped: Binding<Bool>

        private struct Constants {
            static var imagePadding: CGFloat = 9.0
        }

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
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                Text(Copy.Promo.title)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)

                Text(Copy.Promo.introMessage)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.contextualBody)
                    .multilineTextAlignment(.center)

                OnboardingRebrandingImages.AddToDock.promo
                    .frame(width: 306, height: 100)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
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
            }
        }

        private var tutorialContent: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                Text(Copy.Tutorial.title)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)

                Text(Copy.Tutorial.message)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.contextualBody)
                    .multilineTextAlignment(.center)

                ZStack(alignment: .center) {
                    OnboardingRebrandingImages.AddToDock.tutorialBazel
                        .frame(width: 308, height: 231)
                    LottieView(
                        lottieFile: "add-to-dock-promo",
//                        isAnimating: $isAnimating,
//                        animationImageProvider: model,
//                        valueProvider: .init(
//                            provider: ColorValueProvider(model.color),
//                            keypath: AnimationKeypath(keypath: Self.appIconFillKeyPath)
//                        )
                    )
                    .frame(width: 248, height: 225)
                    .onFirstAppear {
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                            isAnimating = true
//                        }
                    }
                }

                Button(action: {
                    showTutorialAction()
                    showTutorial = true
                }) { Text(Copy.Buttons.gotIt) }
                .buttonStyle(onboardingTheme.primaryButtonStyle.style)
            }
        }
    }
}
