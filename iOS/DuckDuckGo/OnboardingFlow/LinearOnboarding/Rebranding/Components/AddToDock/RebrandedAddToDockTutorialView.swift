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

import DuckUI
import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    struct AddToDockTutorialView: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        private static let videoSize = CGSize(width: 898.0, height: 680.0)
        private static let videoURL = Bundle.main.url(forResource: "add-to-dock-demo", withExtension: "mp4")!

        private let title: String
        private let message: String
        private let cta: String
        private let action: () -> Void

        @StateObject private var videoPlayerModel = VideoPlayerCoordinator(configuration: VideoPlayerConfiguration())

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
                    ZStack(alignment: .center) {
                        OnboardingRebrandingImages.AddToDock.tutorialBorder
                            .resizable()
                            .scaledToFit()
                            .padding(.horizontal, -11)
                        videoPlayer
                            .tempPlaceholder()
                            .onFirstAppear {
                                videoPlayerModel.loadAsset(url: Self.videoURL, shouldLoopVideo: true)
                                // Need to delay playing a video. If calling play too early the video won't play.
                                DispatchQueue.main.async {
                                    videoPlayerModel.play()
                                }
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

        private var videoPlayer: some View {
            PlayerView(coordinator: videoPlayerModel)
                .aspectRatio(Self.videoSize.width / Self.videoSize.height, contentMode: .fit)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    videoPlayerModel.pause()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    videoPlayerModel.play()
                }
        }

    }

}
