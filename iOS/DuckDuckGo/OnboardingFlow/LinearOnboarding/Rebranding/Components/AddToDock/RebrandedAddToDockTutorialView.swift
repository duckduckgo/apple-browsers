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
        private static let referenceHeight: CGFloat = 844.0

        private let title: String
        private let message: String
        private let cta: String
        private let action: () -> Void
        private let borderSize: CGSize
        private let borderPadding: EdgeInsets
        private let videoFrameSize: CGSize

        private var scale: CGFloat {
            min(UIScreen.main.bounds.height / Self.referenceHeight, 1.0)
        }

        init(title: String,
             message: String,
             cta: String,
             borderSize: CGSize,
             borderPadding: EdgeInsets,
             videoFrameSize: CGSize,
             action: @escaping () -> Void) {
            self.title = title
            self.message = message
            self.cta = cta
            self.borderSize = borderSize
            self.borderPadding = borderPadding
            self.videoFrameSize = videoFrameSize
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
                    ZStack(alignment: .top) {
                        OnboardingRebrandingImages.AddToDock.tutorialBorder
                            .resizable()
                            .padding(borderPadding)
                            .frame(width: borderSize.width, height: borderSize.height)
                        if let videoURL = Self.videoURL {
                            AddToDockVideoPlayer(url: videoURL,
                                                 frameSize: videoFrameSize,
                                                 shouldLoopVideo: true)
                        }
                    }
                    .scaleEffect(scale)
                    .frame(width: borderSize.width * scale, height: borderSize.height * scale)
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

    }

}
