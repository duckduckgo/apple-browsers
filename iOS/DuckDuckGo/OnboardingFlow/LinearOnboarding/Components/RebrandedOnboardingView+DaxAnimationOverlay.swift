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
struct DaxAnimation: Equatable {

    /// Anchoring position relative to the view's bottom edge.
    enum Position: Equatable {
        /// Bottom-leading anchor. `bottomPadding` lifts above the bottom; `xOffset` shifts right (+) / left (−).
        case left(bottomPadding: CGFloat = 0, xOffset: CGFloat = 0)
        /// Bottom-trailing anchor. `bottomPadding` lifts above the bottom; `xOffset` shifts left (+) / right (−).
        case right(bottomPadding: CGFloat = 0, xOffset: CGFloat = 0)
        /// Bottom-center anchor. `leftCenterOffset` shifts from center (+ = left); `yOffset` lifts (+).
        case bottom(leftCenterOffset: CGFloat = 0, yOffset: CGFloat = 0)
        /// Absolute offset from the bottom-leading corner: x right (+); y up (+).
        case absolute(x: CGFloat, y: CGFloat)
    }

    /// Lottie asset name (`.lottie` or `.json`).
    let animationName: String
    /// Display size in points.
    let size: CGSize
    /// Anchor within the screen.
    let position: Position
    /// When set, the view starts at `finalCenter + entranceOffset` and slides to `finalCenter` on appear.
    let entranceOffset: CGPoint?
    /// When set, the view slides from `finalCenter` to `finalCenter + exitOffset` on exit.
    let exitOffset: CGPoint?
    /// Splits the Lottie into two stages: entrance plays 0 → this progress, exit plays
    /// this progress → 1.0 when `isExiting` becomes `true`. Nil = single-stage (reverse on exit).
    let twoStagesAnimation: Double?
    /// Exit duration; falls back to `daxExitDuration` when nil.
    let exitDuration: TimeInterval?
    /// Fade the overlay to transparent during exit.
    let fadeOut: Bool
    /// Loop the Lottie indefinitely instead of stopping on the last frame.
    let loop: Bool
    /// When set, the overlay fades from 0 → 1 over this duration on appear.
    let fadeInTime: TimeInterval?
    /// Delay before Lottie playback begins on appear.
    let startDelay: TimeInterval

    /// Animation slides off-screen *before* the step transition; parent must delay the action.
    var hasSlideExit: Bool { exitOffset != nil }

    /// Animation fades out *with* the step transition; parent fires the action immediately.
    var hasFadeExit: Bool { fadeOut }

    /// Two-stage exit plays *with* the step transition.
    var hasTwoStagesExit: Bool { twoStagesAnimation != nil }

    /// Custom exit duration, or the shared default.
    var effectiveExitDuration: TimeInterval { exitDuration ?? OnboardingBubbleAnimationMetrics.daxExitDuration }

    init(animationName: String,
         size: CGSize,
         position: DaxAnimation.Position,
         largeScreenPosition: DaxAnimation.Position? = nil,
         entranceOffset: CGPoint? = nil,
         exitOffset: CGPoint? = nil,
         twoStagesAnimation: Double? = nil,
         exitDuration: TimeInterval? = nil,
         fadeOut: Bool = false,
         loop: Bool = false,
         fadeInTime: TimeInterval? = nil,
         startDelay: TimeInterval = 0) {
        self.animationName = animationName
        self.size = size
        if let largeScreenPosition, OnboardingBubbleAnimationMetrics.isLargeScreen {
            self.position = largeScreenPosition
        } else {
            self.position = position
        }
        self.entranceOffset = entranceOffset
        self.exitOffset = exitOffset
        self.twoStagesAnimation = twoStagesAnimation
        self.exitDuration = exitDuration
        self.fadeOut = fadeOut
        self.loop = loop
        self.fadeInTime = fadeInTime
        self.startDelay = startDelay
    }
}

// MARK: - Dax Animation Presets

extension DaxAnimation {

    /// Dax giving a thumbs up, at full base size.
    static let thumbUp = DaxAnimation(
        animationName: "Dax-ThumbUp",
        size: CGSize(width: 258.0, height: 352.0),
        position: .left(bottomPadding: 110.0, xOffset: -40.0),
        largeScreenPosition: .left(bottomPadding: 110.0, xOffset: 200.0),
        entranceOffset: CGPoint(x: -20.0, y: 0),
        exitOffset: CGPoint(x: -258.0, y: 0),
        exitDuration: 0.5,
        fadeOut: true,
        startDelay: 0.75
    )

    /// Dax waving from the bottom center of the screen.
    static let wingBottom = DaxAnimation(
        animationName: "Dax-WingBottom",
        size: CGSize(width: 159.33, height: 180.33),
        position: .bottom(),
        twoStagesAnimation: 0.5,
        exitDuration: 1.0
    )

    /// Dax waving from the left side of the screen.
    static let wingLeft = DaxAnimation(
        animationName: "Dax-WingLeft",
        size: CGSize(width: 116, height: 208.33),
        position: .left(bottomPadding: 70.0),
        twoStagesAnimation: 0.5
    )

    /// Dax waving from the right side of the screen.
    static let wingRight = DaxAnimation(
        animationName: "Dax-WingRight",
        size: CGSize(width: 116, height: 208.33),
        position: .right(bottomPadding: 107.0),
        twoStagesAnimation: 0.5,
        exitDuration: 0.5
    )
}

// MARK: - Dax Animation Overlay

/// Full-screen overlay that plays a Dax Lottie at the configured position. Z-order: background
/// < Dax < dialog.
///
/// - Entrance: starts at `finalCenter + entranceOffset` (when set) and slides to `finalCenter`.
/// - Exit: setting `isExiting = true` slides to `finalCenter + exitOffset`; the parent must
///   wait `daxExitDuration` before destroying the view.
/// - Two-stage: when `twoStagesAnimation` is set, entrance plays 0 → midpoint and exit plays
///   midpoint → 1.0; `playForward` is ignored.
struct DaxAnimationOverlay: View {

    let animation: DaxAnimation
    /// `true` to play forward; `false` to reverse. Ignored for two-stage animations.
    let playForward: Bool
    /// Triggers the slide-out exit (requires `exitOffset`).
    let isExiting: Bool

    /// On Reduce Motion: skip slide-in / fade and freeze Lottie at the intended final frame
    /// (`twoStagesAnimation` when set, otherwise `1.0`).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reducedMotionFinalProgress: AnimationProgressTime {
        animation.twoStagesAnimation.map { AnimationProgressTime($0) } ?? 1.0
    }

    /// Displacement from `finalCenter`. Seeded from `entranceOffset` so the first render is
    /// already off-screen (no jump).
    @State private var positionOffset: CGPoint
    /// Starts at 0 when `fadeInTime` is set, otherwise 1; driven to 0 on `fadeOut` exit.
    @State private var opacity: Double

    /// `false` until `startDelay` elapses; hides the entire overlay.
    @State private var started: Bool

    init(animation: DaxAnimation, playForward: Bool, isExiting: Bool) {
        self.animation = animation
        self.playForward = playForward
        self.isExiting = isExiting
        _positionOffset = State(initialValue: animation.entranceOffset ?? .zero)
        _opacity = State(initialValue: 0)
        _started = State(initialValue: animation.startDelay <= 0)
    }

    /// Lottie playback derived from the current state.
    /// - Reduce Motion: frozen at the intended final frame (parent handles the visual exit).
    /// - Two-stage: entrance plays 0 → midpoint; exit plays midpoint → 1.0.
    /// - Otherwise: `playForward` controls direction, or loops when `animation.loop`.
    private var lottiePlaybackMode: LottiePlaybackMode {
        guard started else {
            return .paused
        }
        if reduceMotion {
            return .paused(at: .progress(reducedMotionFinalProgress))
        }
        if let midPoint = animation.twoStagesAnimation {
            return isExiting
                ? .playing(.fromProgress(midPoint, toProgress: 1.0, loopMode: .playOnce))
                : .playing(.fromProgress(0, toProgress: midPoint, loopMode: .playOnce))
        }
        if animation.loop {
            return .playing(.fromProgress(0, toProgress: 1.0, loopMode: .loop))
        }
        return playForward
            ? .playing(.fromProgress(0, toProgress: 1.0, loopMode: .playOnce))
            : .playing(.fromProgress(1.0, toProgress: 0, loopMode: .playOnce))
    }

    var body: some View {
        GeometryReader { proxy in
            let finalCenter = center(in: proxy.size)

            Lottie.LottieView {
                try await DotLottieFile.asset(named: animation.animationName)
            }
            .playbackMode(lottiePlaybackMode)
            .resizable()
            // Stable ID prevents the async asset closure from re-running on every re-render.
            .id(animation.animationName)
            .frame(width: animation.size.width, height: animation.size.height)
            .position(x: finalCenter.x + positionOffset.x, y: finalCenter.y + positionOffset.y)
        }
        .opacity(opacity)
        // Anchors positions against the screen bottom, not the safe-area bottom.
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            let begin = { [reduceMotion] in
                started = true
                if animation.entranceOffset != nil {
                    if reduceMotion {
                        positionOffset = .zero
                    } else {
                        withAnimation(.easeOut(duration: OnboardingBubbleAnimationMetrics.daxEntranceDuration)) {
                            positionOffset = .zero
                        }
                    }
                }
                if let fadeDuration = animation.fadeInTime, !reduceMotion {
                    withAnimation(.easeIn(duration: fadeDuration)) {
                        opacity = 1
                    }
                } else {
                    opacity = 1
                }
            }
            // Reduce Motion: skip the start delay.
            if animation.startDelay > 0 && !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + animation.startDelay, execute: begin)
            } else {
                begin()
            }
        }
        .onChange(of: isExiting) { [reduceMotion] exiting in
            guard exiting else { return }
            let duration = animation.effectiveExitDuration
            if let offset = animation.exitOffset {
                if reduceMotion {
                    positionOffset = offset
                } else {
                    withAnimation(.easeIn(duration: duration)) {
                        positionOffset = offset
                    }
                }
            }
            if animation.fadeOut {
                if reduceMotion {
                    opacity = 0
                } else {
                    withAnimation(.easeIn(duration: duration)) {
                        opacity = 0
                    }
                }
            }
        }
    }

    /// Center of the animation frame in the container. `.position(x:y:)` takes the midpoint,
    /// so each case adds half the animation size to the anchor.
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
            // x from leading edge (can be negative); y from bottom (positive = above).
            return CGPoint(x: x + animation.size.width / 2,
                           y: bottomAnchoredY(in: size, bottomPadding: y))
        }
    }

    private func bottomAnchoredY(in size: CGSize, bottomPadding: CGFloat) -> CGFloat {
        size.height - bottomPadding - animation.size.height / 2
    }
}
