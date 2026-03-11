//
//  RebrandedAddToDockTutorialView.swift
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

import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    struct AddToDockTutorialView: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private static let videoURL = Bundle.main.url(forResource: "Rebranded-AddToDock-tutorial", withExtension: "mp4")

        private enum Design {
            static let borderWidth: CGFloat = 321
            static let borderHeight: CGFloat = 239
            static let videoWidth: CGFloat = 300
            static let videoHeight: CGFloat = 231
            static let borderHorizontalPadding: CGFloat = -8
            static let borderVerticalPadding: CGFloat = -1
        }

        private let title: String
        private let message: String
        private let cta: String
        private let action: () -> Void

        init(title: String,
             message: String,
             cta: String,
             action: @escaping () -> Void) {
            self.title = title
            self.message = message
            self.cta = cta
            self.action = action
        }

        var body: some View {
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
                content: AnyView(
                    videoContent
                ),
                title: {
                    Text(title)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.title)
                        .multilineTextAlignment(.center)
                },
                actions: {
                    Button(action: action) {
                        Text(cta)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            )
        }

        private var videoContent: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let ratio = width / Design.borderWidth

                ZStack(alignment: .top) {
                    OnboardingRebrandingImages.AddToDock.tutorialBorder
                        .resizable()
                        .padding(EdgeInsets(top: Design.borderVerticalPadding * ratio,
                                            leading: Design.borderHorizontalPadding * ratio,
                                            bottom: Design.borderVerticalPadding * ratio,
                                            trailing: Design.borderHorizontalPadding * ratio))
                        .frame(width: width, height: Design.borderHeight * ratio)
                    if let videoURL = Self.videoURL {
                        AddToDockVideoPlayer(url: videoURL,
                                             frameSize: CGSize(width: Design.videoWidth * ratio,
                                                               height: Design.videoHeight * ratio),
                                             shouldLoopVideo: true,
                                             cornerRadiusRatio: ratio)
                    }
                }
            }
            .aspectRatio(Design.borderWidth / Design.borderHeight, contentMode: .fit)
        }

    }

}
