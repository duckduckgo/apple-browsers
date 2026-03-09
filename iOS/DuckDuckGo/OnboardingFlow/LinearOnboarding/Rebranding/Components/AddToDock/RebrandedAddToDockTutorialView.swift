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
                    ZStack(alignment: .top) {
                        OnboardingRebrandingImages.AddToDock.tutorialBorder
                            .resizable()
                            .padding(.horizontal, -8)
                            .padding(.vertical, -1)
                            .frame(width: 321.0, height: 239.0)
                        if let videoURL = Self.videoURL {
                            AddToDockVideoPlayer(
                                url: videoURL,
                                frameSize: CGSize(width: 300.0, height: 231.0)
                            )
                        }
                    }
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
