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

        private enum Assets {
            static let backgroundLottieFileName = "OnboardingLandingIllustrationAnimation"
            static let logoLottieFileName = "OnboardingLandingLogoAnimation"
        }

        // MARK: - Metrics

        private enum Metrics {
            static let logoSize: CGFloat = 125 // Dax logo frame (square)
            static let topPadding: CGFloat = 96 // Distance from top safe area to logo
            static let welcomeBottomPadding: CGFloat = 20 // Spacing between logo and title text
            static let horizontalPadding: CGFloat = 16

            // Illustration (landscape Lottie, original canvas 4000×1622)
            static let illustrationWidth: CGFloat = 1200 // Final width after animation
            static let illustrationHeight: CGFloat = 487 // Maintains 4000:1622 aspect ratio
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
            // Group (CTRL_Logo): ease-in-out scale, delay ≈ 3 frames
            static let groupScaleAnimation: Animation = .timingCurve(0.66, 0, 0.34, 1, duration: 1.4).delay(0.1)
            // Group (CTRL_Logo): ease-out slide up, delay ≈ 3 frames
            static let groupOffsetAnimation: Animation = .timingCurve(0.4, 0.737, 0.74, 1.0, duration: 1.167).delay(0.1)

            // Logo local scale: ease-out, delay ≈ 11.8 frames
            static let logoScaleAnimation: Animation = .timingCurve(0.26, 0.642, 0.48, 1.0, duration: 0.673).delay(0.393)

            // Text offset: ease-out slide up, delay ≈ 11.8 frames
            static let textOffsetAnimation: Animation = .timingCurve(0.4, 0.774, 0.74, 1.0, duration: 0.507).delay(0.393)

            // Text opacity: simple ease fade-in, synced with offset delay
            static let textOpacityAnimation: Animation = .timingCurve(0.333, 0, 0.667, 1.0, duration: 0.221).delay(0.393)
        }

        @Environment(\.onboardingTheme) private var onboardingTheme

        let animationNamespace: Namespace.ID

        @State private var groupScale = LandingAnimationStates.groupScaleStart
        @State private var groupOffsetY = LandingAnimationStates.groupOffsetYStart
        @State private var logo = LandingAnimationStates.logoStart
        @State private var text = LandingAnimationStates.textStart
        @State private var textOffset = LandingAnimationStates.textOffsetStart

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    logoAndTextView
                        .padding(.top, Metrics.topPadding)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)

                    backgroundView
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onAppear {
                animateEntrance()
            }
        }

        // MARK: - Logo + text

        private var logoAndTextView: some View {
            VStack(alignment: .center, spacing: Metrics.welcomeBottomPadding) {
                // Logo Lottie (internal animation plays the Dax entrance; no opacity fade)
                Lottie.LottieView(animation: .asset(Assets.logoLottieFileName))
                    .playing(loopMode: .playOnce)
                    .resizable()
                    .matchedGeometryEffect(id: OnboardingView.daxGeometryEffectID, in: animationNamespace)
                    .frame(width: Metrics.logoSize, height: Metrics.logoSize)
                    .scaleEffect(logo.scale)

                // Text
                Text(UserText.onboardingWelcomeHeader)
                    .font(onboardingTheme.typography.largeTitle)
                    .foregroundStyle(onboardingTheme.colorPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .offset(textOffset)
                    .opacity(text.opacity)
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .scaleEffect(groupScale)
            .offset(y: groupOffsetY)
        }

        // MARK: - Background

        private var backgroundView: some View {
            // Illustration Lottie — entrance animation is internal (NULL parent scales/slides up).
            // Start from frame 22 to match the reference's st=-22 time offset.
            Lottie.LottieView(animation: .asset(Assets.backgroundLottieFileName))
                .playbackMode(.playing(.fromProgress(22.0 / 89.0, toProgress: 1.0, loopMode: .playOnce)))
                .resizable()
                .clipped()
                .frame(width: Metrics.illustrationWidth, height: Metrics.illustrationHeight)
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
        }
    }
}
