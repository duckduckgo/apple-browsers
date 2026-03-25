//
//  RebrandedOnboardingView+DaxAnimationOverlay.swift
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

import Lottie
import SwiftUI

// MARK: - Dax Animation Configuration

/// Configuration for a Dax Lottie animation overlaid between the scrollable background and the dialog bubble.
struct DaxAnimation {
    
    /// Anchoring position relative to the view's bottom edge.
    enum Position {
        /// Bottom-leading corner anchor; `bottomPadding` lifts above the bottom, `xOffset` shifts right (+) / left (−).
        case left(bottomPadding: CGFloat, xOffset: CGFloat = 0)
        /// Bottom-trailing corner anchor; `bottomPadding` lifts above the bottom, `xOffset` shifts left (+) / right (−).
        case right(bottomPadding: CGFloat, xOffset: CGFloat = 0)
        /// Centered horizontally at the bottom; `leftCenterOffset` shifts from center (positive = left, negative = right), `yOffset` lifts above the bottom (+) / pushes below (−).
        case bottom(leftCenterOffset: CGFloat = 0, yOffset: CGFloat = 0)
        /// Fixed offset from the bottom-leading corner: x right (+) / left (−), y up (+) / down (−).
        case absolute(x: CGFloat, y: CGFloat)
    }

    /// Asset catalog name of the Lottie animation (`.lottie` or `.json`).
    let animationName: String
    /// Display size of the animation in points.
    let size: CGSize
    /// Where to place the animation within the screen.
    let position: Position
    /// When non-nil, the view starts at `finalCenter + entranceOffset` and slides to `finalCenter`
    /// at the same time the Lottie animation begins playing.
    let entranceOffset: CGPoint?
    /// When non-nil, the view slides from `finalCenter` to `finalCenter + exitOffset`
    /// when the animation is played in reverse.
    let exitOffset: CGPoint?

    init(animationName: String,
         size: CGSize,
         position: DaxAnimation.Position,
         entranceOffset: CGPoint? = nil,
         exitOffset: CGPoint? = nil) {
        self.animationName = animationName
        self.size = size
        self.position = position
        self.entranceOffset = entranceOffset
        self.exitOffset = exitOffset
    }
}

// MARK: - Dax Animation Overlay

/// Full-screen overlay that plays a Dax Lottie animation at a design-specified position.
///
/// Rendered between `ScrollableOnboardingBackground` and the dialog bubble in
/// `OnboardingRebranding.OnboardingView`, so the z-order is: background < Dax < dialog.
///
/// ## Entrance
/// If `animation.entranceOffset` is set, the view starts at `finalCenter + entranceOffset` and
/// slides to `finalCenter` on `onAppear`, in sync with Lottie beginning to play.
///
/// ## Exit
/// Set `isExiting = true` to slide the view from `finalCenter` to `finalCenter + animation.exitOffset`.
/// The parent must wait `OnboardingBubbleAnimationMetrics.daxExitDuration` before destroying the view.
struct DaxAnimationOverlay: View {

    let animation: DaxAnimation
    /// `true` to play forward (entrance); `false` to play in reverse (exit).
    let playForward: Bool
    /// Set to `true` to trigger the slide-out exit animation (requires `animation.exitOffset`).
    let isExiting: Bool

    /// Current displacement from `finalCenter`. Zero means the view is at its design position.
    /// Seeded from `entranceOffset` so the very first render is already off-screen — no jump.
    @State private var positionOffset: CGPoint

    init(animation: DaxAnimation, playForward: Bool, isExiting: Bool) {
        self.animation = animation
        self.playForward = playForward
        self.isExiting = isExiting
        _positionOffset = State(initialValue: animation.entranceOffset ?? .zero)
    }

    var body: some View {
        GeometryReader { proxy in
            let finalCenter = center(in: proxy.size)

            Lottie.LottieView {
                try await DotLottieFile.asset(named: animation.animationName)
            }
            // Play once and stop on the last frame of the chosen direction so Dax stays visible.
            .playbackMode(playForward
                ? .playing(.fromProgress(0, toProgress: 1.0, loopMode: .playOnce))
                : .playing(.fromProgress(1.0, toProgress: 0, loopMode: .playOnce))
            )
            .resizable()
            // Stable ID keeps the same LottieView instance across re-renders triggered by
            // positionOffset changes. Without it, the async closure re-runs on each re-render
            // and restarts the animation.
            .id(animation.animationName)
            .frame(width: animation.size.width, height: animation.size.height)
            // Position by center so .position(x:y:) receives the view's midpoint.
            .position(x: finalCenter.x + positionOffset.x, y: finalCenter.y + positionOffset.y)
        }
        // Expand proxy.size to the full screen so positions are computed against the true screen
        // bottom, not the safe-area-inset bottom.
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard animation.entranceOffset != nil else { return }
            // positionOffset is already at entranceOffset from init; animate straight to the
            // final position in sync with Lottie starting to play — no intermediate jump needed.
            withAnimation(.easeOut(duration: OnboardingBubbleAnimationMetrics.daxEntranceDuration)) {
                positionOffset = .zero
            }
        }
        .onChange(of: isExiting) { exiting in
            guard exiting, let offset = animation.exitOffset else { return }
            withAnimation(.easeIn(duration: OnboardingBubbleAnimationMetrics.daxExitDuration)) {
                positionOffset = offset
            }
        }
    }

    /// Returns the center point of the animation frame within a container of the given size.
    ///
    /// `.position(x:y:)` expects the center of the view, so each case adds half the animation
    /// dimensions to the anchor corner's origin.
    private func center(in size: CGSize) -> CGPoint {
        switch animation.position {
        case .left(let bottomPadding, let xOffset):
            return CGPoint(x: animation.size.width / 2 + xOffset,
                           y: bottomAnchoredY(in: size, bottomPadding: bottomPadding))
        case .right(let bottomPadding, let xOffset):
            return CGPoint(x: size.width - animation.size.width / 2 - xOffset,
                           y: bottomAnchoredY(in: size, bottomPadding: bottomPadding))
        case .bottom(let leftCenterOffset, let yOffset):
            return CGPoint(x: size.width / 2 - leftCenterOffset,
                           y: bottomAnchoredY(in: size, bottomPadding: yOffset))
        case .absolute(let x, let y):
            // x: distance from leading edge (may be negative to go off-screen left)
            // y: distance from bottom edge (positive = above the bottom)
            return CGPoint(x: x + animation.size.width / 2,
                           y: bottomAnchoredY(in: size, bottomPadding: y))
        }
    }

    /// Y coordinate of the animation center when anchored at `bottomPadding` points above the bottom.
    private func bottomAnchoredY(in size: CGSize, bottomPadding: CGFloat) -> CGFloat {
        size.height - bottomPadding - animation.size.height / 2
    }
}
