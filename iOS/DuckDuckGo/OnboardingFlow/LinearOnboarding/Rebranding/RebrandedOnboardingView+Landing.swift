//
//  RebrandedOnboardingView+Landing.swift
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
import Lottie

// MARK: - Landing View

extension OnboardingRebranding.OnboardingView {

    struct LandingView: View {

        @Environment(\.colorScheme) private var colorScheme

        private enum Assets {
            static let backgroundLottieFileName = "OnboardingLandingIllustrationAnimation"
            static let backgroundLottieDarkFileName = "OnboardingLandingIllustrationAnimation_dark"
            static let logoLottieFileName = "OnboardingLandingLogoAnimation"
        }

        // MARK: - Metrics

        private enum Metrics {
            static let logoSize: CGFloat = 125 // Dax logo frame (square)
            static let topPadding: CGFloat = 96 // Distance from top safe area to logo
            static let welcomeBottomPadding: CGFloat = 20 // Spacing between logo and title text
            static let horizontalPadding: CGFloat = 16

            // Illustration (landscape Lottie, original canvas 4000×1622)
            static let illustrationWidth: CGFloat = 1200
            static let illustrationHeight: CGFloat = 487 // Maintains 4000:1622 aspect ratio
            static let illustrationScalePad: CGFloat = 1.4

            // Small-screen adjustments (e.g. iPhone SE — screen height ≤ 667 pt)
            static let smallScreenHeightThreshold: CGFloat = 700
            static let textScaleSmallScreen: CGFloat = 0.8
        }

        // MARK: - Component Animation

        private struct ComponentAnimationState {
            var scale: CGFloat
            var opacity: Double

            static func start(
                scale: CGFloat = 1.0,
                opacity: Double = 0.0
            ) -> ComponentAnimationState {
                ComponentAnimationState(scale: scale, opacity: opacity)
            }

            static func end(
                scale: CGFloat = 1.0,
                opacity: Double = 1.0
            ) -> ComponentAnimationState {
                ComponentAnimationState(scale: scale, opacity: opacity)
            }
        }

        // MARK: - Start / End States

        private enum LandingAnimationStates {

            // Group (matches CTRL_Logo parent in AE): scales 141.05% → 108.5%, slides up
            static let groupScaleStart: CGFloat = 141.05 / 108.5  // ≈ 1.3
            static let groupOffsetYStart: CGFloat = 100            // ~11.8% of canvas height (tune by eye)

            // Logo: scales down from local 77.2% → 43.2% (ratio ≈ 1.787). No opacity animation.
            static let logoStart = ComponentAnimationState.start(scale: 77.2 / 43.2, opacity: 1.0)
            static let logoEnd = ComponentAnimationState.end()

            // Text: fades in and slides up (local offset relative to group)
            static let textStart = ComponentAnimationState.start(opacity: 0.0)
            static let textOffsetStart: CGSize = CGSize(width: 0, height: 49)
            static let textEnd = ComponentAnimationState.end()
        }

        // MARK: - Timing (from AE reference at 30fps — iOS_Intro_Prod.json)

        private enum LandingAnimationTiming {

            // MARK: Delays & durations (seconds, derived from AE at 30 fps)

            // Group (CTRL_Logo)
            static let groupScaleDelay: TimeInterval = 0.1
            static let groupScaleDuration: TimeInterval = 1.4
            static let groupOffsetDelay: TimeInterval = 0.1
            static let groupOffsetDuration: TimeInterval = 1.167

            // Logo local scale
            static let logoScaleDelay: TimeInterval = 0.393
            static let logoScaleDuration: TimeInterval = 0.673

            // Text offset & opacity
            static let textOffsetDelay: TimeInterval = 0.393
            static let textOffsetDuration: TimeInterval = 0.507
            static let textOpacityDelay: TimeInterval = 0.393
            static let textOpacityDuration: TimeInterval = 0.221

            // Exit animations (fade out logo and text)
            static let exitFadeDuration: TimeInterval = 0.3

            // Lottie playback parameters
            static let logoLottieFPS: Double = 30
            static let logoLottieTotalFrames: Double = 60
            static let illustrationLottieFPS: Double = 30
            static let illustrationLottieStartFrame: Double = 22
            static let illustrationLottieTotalFrames: Double = 89

            // MARK: Computed durations

            static let logoLottieDuration: TimeInterval = logoLottieTotalFrames / logoLottieFPS
            static let illustrationLottiePlaybackDuration: TimeInterval = (illustrationLottieTotalFrames - illustrationLottieStartFrame) / illustrationLottieFPS

            /// Time from `.onAppear` until every entrance animation (SwiftUI + Lottie) has finished.
            static var entranceDuration: TimeInterval {
                max(
                    groupScaleDelay + groupScaleDuration,
                    groupOffsetDelay + groupOffsetDuration,
                    logoScaleDelay + logoScaleDuration,
                    textOffsetDelay + textOffsetDuration,
                    textOpacityDelay + textOpacityDuration,
                    logoLottieDuration,
                    illustrationLottiePlaybackDuration
                )
            }

            /// Time from `.onAppear` until all animations (entrance + exit) have finished.
            static var totalDuration: TimeInterval {
                entranceDuration + exitFadeDuration
            }

            // MARK: SwiftUI Animations

            static let groupScaleAnimation: Animation = .timingCurve(0.66, 0, 0.34, 1, duration: groupScaleDuration).delay(groupScaleDelay)
            static let groupOffsetAnimation: Animation = .timingCurve(0.4, 0.737, 0.74, 1.0, duration: groupOffsetDuration).delay(groupOffsetDelay)
            static let logoScaleAnimation: Animation = .timingCurve(0.26, 0.642, 0.48, 1.0, duration: logoScaleDuration).delay(logoScaleDelay)
            static let textOffsetAnimation: Animation = .timingCurve(0.4, 0.774, 0.74, 1.0, duration: textOffsetDuration).delay(textOffsetDelay)
            static let textOpacityAnimation: Animation = .timingCurve(0.333, 0, 0.667, 1.0, duration: textOpacityDuration).delay(textOpacityDelay)
            static let exitFadeAnimation: Animation = .easeOut(duration: exitFadeDuration)
        }

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.onboardingTheme) private var onboardingTheme

        let animationNamespace: Namespace.ID
        var onAnimationComplete: () -> Void

        @State private var groupScale = LandingAnimationStates.groupScaleStart
        @State private var groupOffsetY = LandingAnimationStates.groupOffsetYStart
        @State private var logo = LandingAnimationStates.logoStart
        @State private var text = LandingAnimationStates.textStart
        @State private var textOffset = LandingAnimationStates.textOffsetStart

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    backgroundView

                    logoAndTextView(screenHeight: proxy.size.height)
                        .padding(.top, Metrics.topPadding)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onAppear {
                animateEntrance()
            }
        }

        private var illustrationScale: CGFloat {
            horizontalSizeClass == .regular ? Metrics.illustrationScalePad : 1.0
        }

        // MARK: - Logo + text

        private func logoAndTextView(screenHeight: CGFloat) -> some View {
            let isSmallScreen = screenHeight < Metrics.smallScreenHeightThreshold
            let textScale = isSmallScreen ? Metrics.textScaleSmallScreen : 1.0

            return VStack(alignment: .center, spacing: Metrics.welcomeBottomPadding) {
                // Logo Lottie (internal animation plays the Dax entrance; no opacity fade)
                Lottie.LottieView {
                    try await DotLottieFile.asset(named: Assets.logoLottieFileName)
                }
                    .playing(loopMode: .playOnce)
                    .resizable()
                    .matchedGeometryEffect(id: OnboardingView.daxGeometryEffectID, in: animationNamespace)
                    .frame(width: Metrics.logoSize, height: Metrics.logoSize)
                    .scaleEffect(logo.scale)
                    .opacity(logo.opacity)

                // Text
                Text(UserText.onboardingWelcomeHeader)
                    .font(onboardingTheme.typography.largeTitle)
                    .foregroundStyle(onboardingTheme.colorPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .scaleEffect(textScale)
                    .offset(textOffset)
                    .opacity(text.opacity)
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .scaleEffect(groupScale)
            .offset(y: groupOffsetY)
        }

        // MARK: - Background

        private var backgroundLottieAssetName: String {
            colorScheme == .dark ? Assets.backgroundLottieDarkFileName : Assets.backgroundLottieFileName
        }

        private var backgroundView: some View {
            Lottie.LottieView {
                try await DotLottieFile.asset(named: backgroundLottieAssetName)
            }
                .playbackMode(.playing(.fromProgress(
                    LandingAnimationTiming.illustrationLottieStartFrame / LandingAnimationTiming.illustrationLottieTotalFrames,
                    toProgress: 1.0,
                    loopMode: .playOnce
                )))
                .resizable()
                .id(backgroundLottieAssetName)
                .clipped()
                .frame(
                    width: Metrics.illustrationWidth * illustrationScale,
                    height: Metrics.illustrationHeight * illustrationScale
                )
                .allowsHitTesting(false)
        }

        // MARK: - Animation Sequencing

        private func animateEntrance() {
            // Group (CTRL_Logo): scale + offset
            withAnimation(LandingAnimationTiming.groupScaleAnimation) {
                groupScale = 1.0
            }
            withAnimation(LandingAnimationTiming.groupOffsetAnimation) {
                groupOffsetY = 0
            }

            // Logo: local scale only (no opacity — internal Lottie creates the entrance)
            withAnimation(LandingAnimationTiming.logoScaleAnimation) {
                logo = LandingAnimationStates.logoEnd
            }

            // Text: offset + opacity
            withAnimation(LandingAnimationTiming.textOffsetAnimation) {
                textOffset = .zero
            }
            withAnimation(LandingAnimationTiming.textOpacityAnimation) {
                text = LandingAnimationStates.textEnd
            }

            // Background: no SwiftUI animation — Lottie plays from frame 22 internally

            // After entrance animations complete, fade out logo and text
            DispatchQueue.main.asyncAfter(deadline: .now() + LandingAnimationTiming.entranceDuration) {
                animateExit()
            }

            // Notify parent when all animations (entrance + exit) have finished
            DispatchQueue.main.asyncAfter(deadline: .now() + LandingAnimationTiming.totalDuration) {
                onAnimationComplete()
            }
        }

        private func animateExit() {
            // Fade out logo and text
            withAnimation(LandingAnimationTiming.exitFadeAnimation) {
                logo.opacity = 0
                text.opacity = 0
            }
        }
    }
}
