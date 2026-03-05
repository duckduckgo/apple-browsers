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

        private static let videoSize = CGSize(width: 900.0, height: 696.0)
        private static let videoURL = Bundle.main.url(forResource: "Rebranded-AddToDock", withExtension: "mp4")!

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
                    ZStack(alignment: .top) {
                        OnboardingRebrandingImages.AddToDock.tutorialBorder
                            .resizable()
                            .padding(.horizontal, -11)
                            .padding(.vertical, -1)
                            .frame(width: 321.0, height: 237.0)
                        videoPlayer
                            .onFirstAppear {
                                videoPlayerModel.loadAsset(url: Self.videoURL, shouldLoopVideo: true)
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
                .frame(width: 300.0, height: 231.0)
                .clipShape(BottomRoundedRectangle(radius: 34))
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    videoPlayerModel.play()
                }
        }

    }

}

// MARK: - Bottom Rounded Rectangle

private struct BottomRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .init(x: rect.minX, y: rect.minY))
        path.addLine(to: .init(x: rect.maxX, y: rect.minY))
        path.addLine(to: .init(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: .init(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .zero,
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: .init(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: .init(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
