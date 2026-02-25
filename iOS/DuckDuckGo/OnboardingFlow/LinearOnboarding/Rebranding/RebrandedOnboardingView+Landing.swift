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
            static let illustrationAnimation = "OnboardingLandingIllustrationAnimation"  // Mountains/landscape
            static let logoAnimation = "OnboardingLandingLogoAnimation"                  // Dax logo
        }

        // MARK: - Metrics

        private enum Metrics {
            static let logoSize: CGFloat = 125         // Dax logo frame (square)
            static let topPadding: CGFloat = 96        // Distance from top safe area to logo
            static let welcomeBottomPadding: CGFloat = 20  // Spacing between logo and title text
            static let horizontalPadding: CGFloat = 16

            // Illustration (landscape Lottie, original canvas 4000×1622)
            static let illustrationWidth: CGFloat = 1200   // Final width after animation
            static let illustrationHeight: CGFloat = 487   // Maintains 4000:1622 aspect ratio
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

            // Logo: scales down from 178% (AE 25% → 14% of canvas = 1.786x ratio) and fades in
            static let logoStart = ComponentAnimationState.start(scale: 25.0 / 14.0, opacity: 0.0)
            static let logoEnd = ComponentAnimationState.end()

            // Text: fades in and slides up 49pt from below
            static let textStart = ComponentAnimationState.start(opacity: 0.0)
            static let textOffsetStart: CGSize = CGSize(width: 0, height: 49)
            static let textEnd = ComponentAnimationState.end()

            // Illustration: fades in and slides from off-screen (325pt right, 204pt below)
            static let illustrationStart = ComponentAnimationState.start()
            static let illustrationOffsetStart: CGSize = CGSize(width: 325, height: 204)
            static let illustrationEnd = ComponentAnimationState.end()
        }

        // MARK: - Timing (from AE specs at 30fps)

        private enum LandingAnimationTiming {
            // Logo: soft ease-out for scale + opacity, 0.4s delay to let illustration start first
            static let logoAnimation: Animation = .timingCurve(0.26, 0.64, 0.48, 1.00, duration: 0.667).delay(0.4)

            // Text offset: cubic-bezier with y1=2.70 creates an overshoot (slides past target, bounces back)
            static let textOffsetAnimation: Animation = .timingCurve(0.40, 2.70, 0.74, 1.00, duration: 0.5).delay(0.4)

            // Text opacity: simple ease for fade-in, synced with offset delay
            static let textOpacityAnimation: Animation = .timingCurve(0.33, 0.00, 0.67, 1.00, duration: 0.2).delay(0.4)

            // Illustration: slides in from bottom-right, starts almost immediately (0.133s ≈ 4 frames at 30fps)
            static let illustrationAnimation: Animation = .timingCurve(0.10, 0.85, 0.64, 0.99, duration: 0.7).delay(0.133)
        }

        @Environment(\.onboardingTheme) private var onboardingTheme

        let animationNamespace: Namespace.ID

        @State private var logo = LandingAnimationStates.logoStart
        @State private var logoAnimationFinished = false
        @State private var text = LandingAnimationStates.textStart
        @State private var textOffset = LandingAnimationStates.textOffsetStart
        @State private var illustration = LandingAnimationStates.illustrationStart
        @State private var illustrationOffset = LandingAnimationStates.illustrationOffsetStart

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
                // Logo Lottie (plays once then holds on the last frame)
                Lottie.LottieView(animation: .asset(Assets.logoAnimation))
                    .playing(loopMode: .playOnce)
                    .resizable()
                    .matchedGeometryEffect(id: RebrandedOnboardingView.daxGeometryEffectID, in: animationNamespace)
                    .frame(width: Metrics.logoSize, height: Metrics.logoSize)
                    .scaleEffect(logo.scale)
                    .opacity(logo.opacity)

                // Text
                Text(UserText.onboardingWelcomeHeader)
                    .font(onboardingTheme.typography.largeTitle)
                    .foregroundStyle(onboardingTheme.colorPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .offset(textOffset)
                    .opacity(text.opacity)
            }
            .padding(.horizontal, Metrics.horizontalPadding)
        }

        // MARK: - Background

        private var backgroundView: some View {
            Lottie.LottieView(animation: .asset(Assets.illustrationAnimation))
                //.playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
                .playing(loopMode: .playOnce)
                .resizable()
                .clipped()
                .frame(width: Metrics.illustrationWidth, height: Metrics.illustrationHeight)
                .offset(illustrationOffset)
                .opacity(illustration.opacity)
                .allowsHitTesting(false)
        }

        // MARK: - Animation Sequencing

        private func animateEntrance() {
            // Logo: scale + opacity
            withAnimation(LandingAnimationTiming.logoAnimation) {
                logo = LandingAnimationStates.logoEnd
            }

            // Text: offset with overshoot curve
            withAnimation(LandingAnimationTiming.textOffsetAnimation) {
                textOffset = .zero
            }
            // Text: opacity with separate curve
            withAnimation(LandingAnimationTiming.textOpacityAnimation) {
                text = LandingAnimationStates.textEnd
            }

            // Illustration: position slide-in
            withAnimation(LandingAnimationTiming.illustrationAnimation) {
                illustrationOffset = .zero
                illustration = LandingAnimationStates.illustrationEnd
            }
        }
    }
}
