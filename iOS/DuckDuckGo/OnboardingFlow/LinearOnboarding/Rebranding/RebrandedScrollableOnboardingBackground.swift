//
//  RebrandedScrollableOnboardingBackground.swift
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

struct ScrollableOnboardingBackground: View {

    private enum Metrics {
        static let exitDuration: TimeInterval = 1.0
        static let enterDuration: TimeInterval = 1.5
        static let backgroundImageWidth: CGFloat = 1366
    }

    let viewState: OnboardingView.ViewState.Intro

    @State private var previousViewState: OnboardingView.ViewState.Intro?
    @State private var exitingTransitionProgress: CGFloat = 1.0  // 0.0 = start, 1.0 = end
    @State private var enteringTransitionProgress: CGFloat = 1.0  // 0.0 = start, 1.0 = end

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Previous background (exiting)
                if let previousState = previousViewState,
                   previousState.type.backgroundImage != viewState.type.backgroundImage {
                    ExitingBackgroundView(
                        progress: exitingTransitionProgress,
                        screenWidth: proxy.size.width,
                        imageWidth: Metrics.backgroundImageWidth) {
                            backgroundView(for: previousState, width: proxy.size.width)
                        }
                        .zIndex(0)
                }

                // Current background (entering or static)
                backgroundView(for: viewState, width: proxy.size.width)
                    // Slide in from right with leadingOffset pixels already visible
                    // Base offset positions image's leading edge at screen's trailing edge
                    // Subtracting leadingOffset shifts image left to cater for empty space between illustration and leading edge.
                    // At progress=0.0: image starts with leadingOffset visible from right edge
                    // At progress=1.0: image is centered (offset=0)
                    .offset(x: ((proxy.size.width + Metrics.backgroundImageWidth / 2) - viewState.type.leadingOffset) * (1 - enteringTransitionProgress))
                    .zIndex(1)
            }
            .frame(width: proxy.size.width, alignment: .bottomLeading)
        }
        .onChange(of: viewState) { newState in
            // Only animate if the background actually changes
            guard let previous = previousViewState,
                  previous.type.backgroundImage != newState.type.backgroundImage else { return }

            // Reset progress for new transition
            exitingTransitionProgress = 0.0
            enteringTransitionProgress = 0.0

            // Animate exiting background (slides left + fades)
            withAnimation(.easeInOut(duration: Metrics.exitDuration)) {
                exitingTransitionProgress = 1.0
            }

            // Animate entering background (slides in from right, overlaps with exit)
            if #available(iOS 17, *) {
                withAnimation(.easeInOut(duration: Metrics.enterDuration)) {
                    enteringTransitionProgress = 1.0
                } completion: {
                    // Update previous state after animation completes (iOS 17+)
                    previousViewState = newState
                }
            } else {
                // Calculate total duration: the longer of the two overlapping animations
                let totalDuration = max(Metrics.exitDuration, Metrics.enterDuration)

                withAnimation(.easeInOut(duration: Metrics.enterDuration)) {
                    enteringTransitionProgress = 1.0
                }

                // Fallback for iOS 16 and earlier
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                    previousViewState = newState
                }
            }
        }
        .onAppear {
            previousViewState = viewState
            enteringTransitionProgress = 0.0  // Start off-screen to the right

            // Animate sliding in from right
            withAnimation(.easeInOut(duration: Metrics.enterDuration)) {
                enteringTransitionProgress = 1.0
            }
        }
    }

    private func backgroundView(for state: OnboardingView.ViewState.Intro, width: CGFloat) -> some View {
        VStack {
            Spacer()
            state.type.backgroundImage
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, alignment: .center)
                .frame(maxHeight: state.type.backgroundMaxHeight)
        }
        .ignoresSafeArea()
    }

}

// MARK: - Animation Effects

/// A container view that animates a background image sliding out to the left while fading.
///
/// This view conforms to `Animatable` to enable smooth frame-by-frame interpolation during
/// the exit animation. By isolating the animation logic in a dedicated view, we ensure only
/// this view's `body` is called on each animation frame, not the entire parent view hierarchy.
private struct ExitingBackgroundView<Content: View>: View, Animatable {
    var progress: CGFloat
    let screenWidth: CGFloat
    let imageWidth: CGFloat
    let content: Content

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    init(
        progress: CGFloat,
        screenWidth: CGFloat,
        imageWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.progress = progress
        self.screenWidth = screenWidth
        self.imageWidth = imageWidth
        self.content = content()
    }

    var body: some View {
        // Slide left until image's trailing edge aligns with screen's leading edge
        // Image is centered in frame, so: offset = -(frameCenter + imageHalfWidth)
        // At progress=1.0: image trailing edge reaches x=0 (screen leading edge)
        // Fade out background twice as fast as it slides out, clamped to avoid negative opacity.
        content
            .offset(x: -(screenWidth / 2 + imageWidth / 2) * progress)
            .opacity(max(0, 1.0 - progress * 2))
    }
}

private extension OnboardingView.ViewState.Intro.IntroType {
    
    var backgroundImage: Image {
        switch self {
        case .startOnboardingDialog:
            return OnboardingRebrandingImages.Linear.introBackground
        case .browsersComparisonDialog:
            return OnboardingRebrandingImages.Linear.browsersComparisonBackground
        case .addToDockPromoDialog:
            return OnboardingRebrandingImages.Linear.addToDockBackground
        case .chooseAppIconDialog:
            return OnboardingRebrandingImages.Linear.appIconColorSelectionBackground
        case .chooseAddressBarPositionDialog:
            return OnboardingRebrandingImages.Linear.addressBarPositionBackground
        case .chooseSearchExperienceDialog:
            return OnboardingRebrandingImages.Linear.addressBarSearchPreferenceBackground
        }
    }

    /// Maximum height for the background image.
    ///
    /// Design-specified measurements that ensure each background illustration is displayed at the correct scale.
    /// [Figma Assets](https://www.figma.com/design/wMxBpe0mKrRS0nVhtwMGO7/%F0%9F%9A%80-Onboarding-Components--2026-?node-id=3444-40549)
    var backgroundMaxHeight: CGFloat {
        switch self {
        case .startOnboardingDialog:
            return 404
        case .browsersComparisonDialog:
            return 216
        case .addToDockPromoDialog:
            return 286
        case .chooseAppIconDialog:
            return 272
        case .chooseAddressBarPositionDialog:
            return 360
        case .chooseSearchExperienceDialog:
            return 294
        }
    }

    /// Horizontal offset in points determining how much of the entering background is initially visible.
    ///
    /// This value accounts for negative space (empty area) on the left side of each illustration asset.
    /// Each background image has whitespace between its left edge and where the actual illustration begins.
    /// By using a non-zero offset, the illustration content becomes visible sooner during the slide-in animation.
    ///
    /// A value of 0 means the image's leading edge starts exactly at the screen's trailing edge (fully off-screen).
    /// Higher values mean more of the image is initially visible from the right edge of the screen.
    ///
    /// Design-specified values that vary per onboarding step to match each illustration's empty space.
    /// [Figma Assets](https://www.figma.com/design/wMxBpe0mKrRS0nVhtwMGO7/%F0%9F%9A%80-Onboarding-Components--2026-?node-id=3444-40549)
    var leadingOffset: CGFloat {
        switch self {
        case .startOnboardingDialog:
            return 320
        case .browsersComparisonDialog:
            return 380
        case .addToDockPromoDialog:
            return 194
        case .chooseAppIconDialog:
            return 300
        case .chooseAddressBarPositionDialog:
            return 246
        case .chooseSearchExperienceDialog:
            return 164
        }
    }

}
