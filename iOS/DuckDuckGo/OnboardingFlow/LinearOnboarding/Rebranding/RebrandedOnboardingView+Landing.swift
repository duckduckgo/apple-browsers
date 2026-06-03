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

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12191-31845
    struct LandingView: View {

        @Environment(\.colorScheme) private var colorScheme

        private enum Assets {
            static let backgroundLottieFileName = "OnboardingLandingIllustrationAnimation"
            static let backgroundLottieDarkFileName = "OnboardingLandingIllustrationAnimation_dark"
            static let logoLottieFileName = "OnboardingLandingLogoAnimation"
            static let duckAIAnimationFileName = "OnboardingLandingDuckAiAnimation"
            static let duckAIAnimationDarkFileName = "OnboardingLandingDuckAiAnimation_dark"
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

            // DuckAI animation (Lottie canvas 800×400, 2:1)
            static let duckAIAnimationWidth: CGFloat = 280
            static let duckAIAnimationHeight: CGFloat = 140
            static let titleToDuckAISpacing: CGFloat = 0
            // Lottie has ~32% transparent space above the visible glyph; pull it up under the title.
            static let duckAITopOffset: CGFloat = 22
            static let duckAIXOffset: CGFloat = 10

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

            /// How long the landing screen stays visible under Reduce Motion before advancing.
            static let reduceMotionHoldDuration: TimeInterval = 3.0

            // Lottie playback parameters
            static let logoLottieFPS: Double = 30
            static let logoLottieTotalFrames: Double = 60
            static let illustrationLottieFPS: Double = 30
            static let illustrationLottieStartFrame: Double = 22
            static let illustrationLottieTotalFrames: Double = 89
            // DuckAI Lottie (ip=25, op=56 @ 30fps)
            static let duckAILottieFPS: Double = 30
            static let duckAILottieStartFrame: Double = 25
            static let duckAILottieEndFrame: Double = 56

            /// Start the DuckAI Lottie at ~90% through the title's slide-in.
            static let duckAIAnimationDelay: TimeInterval = textOffsetDelay + 0.9 * textOffsetDuration

            // MARK: Computed durations

            static let logoLottieDuration: TimeInterval = logoLottieTotalFrames / logoLottieFPS
            static let illustrationLottiePlaybackDuration: TimeInterval = (illustrationLottieTotalFrames - illustrationLottieStartFrame) / illustrationLottieFPS
            static let duckAILottiePlaybackDuration: TimeInterval = (duckAILottieEndFrame - duckAILottieStartFrame) / duckAILottieFPS

            /// Time from `.onAppear` until every entrance animation (SwiftUI + Lottie) has finished.
            static func entranceDuration(includingDuckAI showsDuckAI: Bool) -> TimeInterval {
                let defaultAnimationsEntranceMaxDuration = max(
                    groupScaleDelay + groupScaleDuration,
                    groupOffsetDelay + groupOffsetDuration,
                    logoScaleDelay + logoScaleDuration,
                    textOffsetDelay + textOffsetDuration,
                    textOpacityDelay + textOpacityDuration,
                    logoLottieDuration,
                    illustrationLottiePlaybackDuration
                )
                let duckAIAnimationEntranceDuration = showsDuckAI ? duckAIAnimationDelay + duckAILottiePlaybackDuration : 0

                return max(defaultAnimationsEntranceMaxDuration, duckAIAnimationEntranceDuration)
            }

            /// Time from `.onAppear` until all animations (entrance + exit) have finished.
            static func totalDuration(includingDuckAI showsDuckAI: Bool) -> TimeInterval {
                entranceDuration(includingDuckAI: showsDuckAI) + exitFadeDuration
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
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let content: OnboardingLandingContent
        let animationNamespace: Namespace.ID
        var onAnimationComplete: () -> Void

        @State private var groupScale = LandingAnimationStates.groupScaleStart
        @State private var groupOffsetY = LandingAnimationStates.groupOffsetYStart
        @State private var logo = LandingAnimationStates.logoStart
        @State private var text = LandingAnimationStates.textStart
        @State private var textOffset = LandingAnimationStates.textOffsetStart
        @State private var duckAIPlay = false

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
            // Restart the entire landing screen (state + animations + theme-dependent Lotties)
            // when the appearance switches mid-flight, rather than some animations restarting and some not.
            .id(colorScheme)
            .onAppear {
                animateEntrance()
            }
        }

        private var illustrationScale: CGFloat {
            horizontalSizeClass == .regular ? Metrics.illustrationScalePad : 1.0
        }

        private var duckAIPlaybackMode: LottiePlaybackMode {
            if reduceMotion {
                return .paused(at: .progress(1.0))
            }
            guard duckAIPlay else {
                return .paused(at: .progress(0))
            }
            return .playing(.fromProgress(0, toProgress: 1.0, loopMode: .playOnce))
        }

        // MARK: - Logo + text

        private func logoAndTextView(screenHeight: CGFloat) -> some View {
            let isSmallScreen = screenHeight < Metrics.smallScreenHeightThreshold
            let textScale = isSmallScreen ? Metrics.textScaleSmallScreen : 1.0

            return VStack(alignment: .center, spacing: Metrics.welcomeBottomPadding) {
                // Logo: Lottie plays Dax's entrance; Reduce Motion freezes on the last frame.
                Lottie.LottieView {
                    try await DotLottieFile.asset(named: Assets.logoLottieFileName)
                }
                    .playbackMode(reduceMotion
                                  ? .paused(at: .progress(1.0))
                                  : .playing(.fromProgress(0, toProgress: 1.0, loopMode: .playOnce)))
                    .resizable()
                    .matchedGeometryEffect(id: OnboardingView.daxGeometryEffectID, in: animationNamespace)
                    .frame(width: Metrics.logoSize, height: Metrics.logoSize)
                    .scaleEffect(logo.scale)
                    .opacity(logo.opacity)

                // Text (+ optional DuckAI animation underneath, sharing the text's offset/opacity)
                VStack(alignment: .center, spacing: Metrics.titleToDuckAISpacing) {
                    Text(content.title)
                        .font(onboardingTheme.typography.largeTitle)
                        .foregroundStyle(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)

                    if content.shouldShowDuckAIAnimation {
                        let fileName = colorScheme == .dark ? Assets.duckAIAnimationDarkFileName : Assets.duckAIAnimationFileName

                        Lottie.LottieView{
                            try await DotLottieFile.asset(named: fileName)
                        }
                        .playbackMode(duckAIPlaybackMode)
                        .resizable()
                        .frame(width: Metrics.duckAIAnimationWidth, height: Metrics.duckAIAnimationHeight)
                        .scaledToFit()
                        .padding(.top, -Metrics.duckAITopOffset)
                        .offset(x: -Metrics.duckAIXOffset)
                        .id(fileName)
                    }
                }
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
            // Reduce Motion: freeze the illustration at its last frame.
            let playback: LottiePlaybackMode = reduceMotion
                ? .paused(at: .progress(1.0))
                : .playing(.fromProgress(
                    LandingAnimationTiming.illustrationLottieStartFrame / LandingAnimationTiming.illustrationLottieTotalFrames,
                    toProgress: 1.0,
                    loopMode: .playOnce
                ))

            return Lottie.LottieView {
                try await DotLottieFile.asset(named: backgroundLottieAssetName)
            }
                .playbackMode(playback)
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
            // Reduce Motion: snap to the end-state, hold for `reduceMotionHoldDuration`, then
            // advance. No exit fade.
            guard !reduceMotion else {
                groupScale = 1.0
                groupOffsetY = 0
                logo = LandingAnimationStates.logoEnd
                textOffset = .zero
                text = LandingAnimationStates.textEnd
                if content.shouldShowDuckAIAnimation {
                    duckAIPlay = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + LandingAnimationTiming.reduceMotionHoldDuration) {
                    onAnimationComplete()
                }
                return
            }

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

            // DuckAI Lottie: start playback partway through the title's slide-in
            if content.shouldShowDuckAIAnimation {
                DispatchQueue.main.asyncAfter(deadline: .now() + LandingAnimationTiming.duckAIAnimationDelay) {
                    duckAIPlay = true
                }
            }

            let showsDuckAI = content.shouldShowDuckAIAnimation

            // After entrance animations complete, fade out logo and text
            DispatchQueue.main.asyncAfter(deadline: .now() + LandingAnimationTiming.entranceDuration(includingDuckAI: showsDuckAI)) {
                animateExit()
            }

            // Notify parent when all animations (entrance + exit) have finished
            DispatchQueue.main.asyncAfter(deadline: .now() + LandingAnimationTiming.totalDuration(includingDuckAI: showsDuckAI)) {
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
