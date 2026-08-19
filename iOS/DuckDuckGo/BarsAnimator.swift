//
//  BarsAnimator.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import UIKit

class BarsAnimator {

    struct Metrics {
        /// Scroll distance for a full floating-chrome collapse or reveal. Tuned against iOS 26 Safari,
        /// which fully collapses in ~75pt. Deliberately absolute rather than a multiple of
        /// `combinedBarsHeight`, because that value is ~188pt with a bottom address bar but ~122pt with
        /// a top one, which would gear the two positions differently.
        static let floatingTransitionTravel: CGFloat = 80

        /// Ceiling on how fast progress may advance while collapsing, in progress-per-second, so a
        /// full collapse can never take less than ~140ms (Safari's flick collapse measures ~0.15s).
        /// Without it a 3000pt/s flick crosses `floatingTransitionTravel` in ~25ms and the bars pop.
        static let maxCollapseProgressPerSecond: CGFloat = 7.0

        /// Longest frame delta the rate limiter will honour, so a stalled frame can't grant a huge step.
        static let maxRateLimitTimeStep: CFTimeInterval = 1.0 / 30.0

        /// Assumed delta for the first frame of a transition, which has no previous timestamp to measure
        /// against. Without it the rate limiter would pin the opening frame to zero progress.
        static let nominalFrameDuration: CFTimeInterval = 1.0 / 60.0

        /// Legacy (non-floating) gearing, preserved exactly.
        static let legacyTransitionSpeed: CGFloat = 0.5

        /// Below this speed a release is treated as deliberate rather than a flick: the outcome is
        /// decided by how far the transition actually progressed, not by the sign of a velocity that's
        /// essentially measurement noise (a real touch release is almost never exactly zero). Units
        /// match `UIScrollViewDelegate`'s `withVelocity:` (points per millisecond); 0.15 sits well
        /// below a deliberate flick's typical 0.5+ while safely above the residual velocity left by a
        /// finger easing to a stop.
        static let floatingVelocityCommitThreshold: CGFloat = 0.15

        /// Exit velocity (matching `floatingVelocityCommitThreshold`'s pt/ms units) at and above which a
        /// flick-triggered settle runs at its fastest. Below `floatingVelocityCommitThreshold` a release
        /// isn't a flick at all (see the deliberate-release branch); between the two thresholds the
        /// settle duration scales continuously, so a firmer flick visibly finishes quicker — the same
        /// motion just carrying more of the speed it already had, rather than always restarting the
        /// animation from a fixed duration regardless of how fast the content was moving.
        static let flickReferenceVelocity: CGFloat = 1.2

        /// Floor on the settle duration for the hardest flicks, seconds.
        static let flickFastestCollapseDuration: CFTimeInterval = 0.08
        static let flickFastestExpandDuration: CFTimeInterval = 0.14

        /// Scroll distance from a drag's anchor beyond which the floating chrome commits fully to the
        /// next state instead of continuing to track the finger, matching Safari's playful snap. Once
        /// crossed, the transition completes via the same animated `hideBars`/`revealBars` a release
        /// would trigger, so a finger that then holds the scroll steady mid-drag lets the animation run
        /// to completion instead of parking the bar at whatever fraction the hold happened to catch.
        static let floatingSnapCommitDistance: CGFloat = 16
    }

    weak var delegate: BrowserChromeDelegate?

    private(set) var barsState: State = .revealed
    private var transitionProgress: CGFloat = 0.0

    var draggingStartPosY: CGFloat = 0

    var transitionStartPosY: CGFloat = 0

    /// Progress at the moment the current transition was entered. The floating path measures scroll
    /// distance from that anchor instead of compounding the previous frame's ratio, so an interrupted
    /// drag resumes from where it visually is.
    private var transitionStartProgress: CGFloat = 0

    /// `nil` until the first rate-limited frame of a transition.
    private var lastProgressTimestamp: CFTimeInterval?

    private enum SnapDirection {
        case collapsing
        case revealing
    }

    /// Set once the current drag has committed past `Metrics.floatingSnapCommitDistance`; `nil` for
    /// the rest of the drag until a firm reversal (the same distance, measured from the commit point)
    /// flips it. `nil` at the start of every drag (reset in `didStartScrolling`).
    private var floatingCommittedDirection: SnapDirection?
    private var floatingCommitOffsetY: CGFloat?

    /// Injected so tests can drive the collapse rate limiter deterministically.
    private let currentTime: () -> CFTimeInterval

    private var bottomRevealGestureState: BottomBounceRevealing = .possible

    #if DEBUG
    /// Test seam so a test can confirm it has landed on an intended progress before asserting on it.
    var transitionProgressForTesting: CGFloat { transitionProgress }
    #endif

    private var combinedBarsHeight: CGFloat {
        guard let delegate = delegate else { return 0 }
        return delegate.toolbarHeight + delegate.omniBar.barView.expectedHeight
    }

    enum State: String {
        case revealed
        case transitioning
        case hidden
    }

    enum BottomBounceRevealing: String {
        case possible
        case triggered
        case cancelled
    }

    init(currentTime: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.currentTime = currentTime
    }

    func didStartScrolling(in scrollView: UIScrollView) {
        draggingStartPosY = scrollView.contentOffset.y

        if delegate?.isFloatingChromeEnabled == true {
            // Anchored once, here, for the floating path -- not re-anchored on every state entry the
            // way the legacy path re-anchors in `revealedAndScrolling`/`hiddenAndScrolling` below. A
            // fixed anchor makes `calculateTransitionRatio` a pure function of the current offset for
            // the whole drag, so reversing direction any number of times within one continuous touch
            // (down, up, down again) just moves the ratio back and forth -- no re-entry guards to fall
            // through, no stale anchor left over from before a reversal.
            transitionStartPosY = scrollView.contentOffset.y
            transitionStartProgress = transitionProgress
            lastProgressTimestamp = nil
            floatingCommittedDirection = nil
            floatingCommitOffsetY = nil
        }
    }

    func didScroll(in scrollView: UIScrollView) {
        guard delegate?.isFloatingChromeEnabled == true else {
            switch barsState {
            case .revealed:
                revealedAndScrolling(in: scrollView)
            case .transitioning:
                transitioningAndScrolling(in: scrollView)
            case .hidden:
                hiddenAndScrolling(in: scrollView)
            }
            return
        }
        floatingDidScroll(in: scrollView)
    }

    /// Single continuous tracker for the floating path: live 1:1 position tracking in both directions
    /// for the whole drag, from the fixed anchor `didStartScrolling` set. Replaces the legacy path's
    /// three-function, re-anchor-on-entry dispatch below, which doesn't handle a drag reversing more
    /// than once (each function's own entry guard compares against state that's stale after the first
    /// reversal).
    private func floatingDidScroll(in scrollView: UIScrollView) {
        if barsState == .hidden {
            let startedDraggingAtBottom = draggingStartPosY >= scrollView.contentOffsetYAtBottom
            if startedDraggingAtBottom, bottomRevealGestureState == .possible {
                if scrollView.contentOffset.y > scrollView.contentOffsetYAtBottom {
                    revealBars(animated: true)
                    bottomRevealGestureState = .triggered
                    return
                } else {
                    // If user starts scrolling up, invalidate the possible reverse (scroll down) gesture.
                    bottomRevealGestureState = .cancelled
                }
            }
        }
        guard bottomRevealGestureState != .triggered else { return }

        if let committed = floatingCommittedDirection, let commitOffsetY = floatingCommitOffsetY {
            let reversal = scrollView.contentOffset.y - commitOffsetY
            switch committed {
            case .collapsing where reversal <= -Metrics.floatingSnapCommitDistance:
                commitFloatingTransition(.revealing, at: scrollView.contentOffset.y)
            case .revealing where reversal >= Metrics.floatingSnapCommitDistance:
                commitFloatingTransition(.collapsing, at: scrollView.contentOffset.y)
            default:
                break
            }
            return
        }

        let distanceFromAnchor = scrollView.contentOffset.y - transitionStartPosY
        if distanceFromAnchor >= Metrics.floatingSnapCommitDistance {
            commitFloatingTransition(.collapsing, at: scrollView.contentOffset.y)
            return
        } else if distanceFromAnchor <= -Metrics.floatingSnapCommitDistance {
            commitFloatingTransition(.revealing, at: scrollView.contentOffset.y)
            return
        }

        let ratio = calculateTransitionRatio(for: scrollView.contentOffset.y)
        if ratio >= 1.0 {
            barsState = .hidden
        } else if ratio <= 0.0 {
            barsState = .revealed
        } else {
            barsState = .transitioning
        }
        transitionProgress = ratio
        delegate?.setBarsVisibility(1.0 - ratio, animated: false, animationDuration: nil)
    }

    private func commitFloatingTransition(_ direction: SnapDirection, at offsetY: CGFloat) {
        floatingCommittedDirection = direction
        floatingCommitOffsetY = offsetY
        switch direction {
        case .collapsing:
            hideBars(animated: true)
        case .revealing:
            revealBars(animated: true)
        }
    }

    // MARK: - Legacy (non-floating) scrolling. Unchanged: re-anchors on every state entry.

    private func revealedAndScrolling(in scrollView: UIScrollView) {
        guard scrollView.contentOffset.y > draggingStartPosY else { return }
        guard scrollView.contentOffset.y < scrollView.contentOffsetYAtBottom - combinedBarsHeight else { return }
        guard bottomRevealGestureState != .triggered else { return }

        // In case view has been "caught" in the middle of the animation above the (0.0, 0.0) offset,
        // wait till user scrolls to the top before animating any transition.
        if draggingStartPosY < 0, scrollView.contentOffset.y <= 0 {
            return
        }

        transitionStartPosY = draggingStartPosY < 0 ? 0 : draggingStartPosY
        transitionStartProgress = transitionProgress
        barsState = .transitioning

        let ratio = calculateTransitionRatio(for: scrollView.contentOffset.y)
        delegate?.setBarsVisibility(1.0 - ratio, animated: false, animationDuration: nil)
        transitionProgress = ratio
    }

    private func transitioningAndScrolling(in scrollView: UIScrollView) {
        let ratio = calculateTransitionRatio(for: scrollView.contentOffset.y)

        // Check if we need to perform additional changes
        let ratioMatchesCurrentState =
        ((barsState == .hidden && ratio == 1.0) || (barsState == .revealed && ratio == 0)) &&
        transitionProgress == ratio

        guard !ratioMatchesCurrentState else {
            return
        }

        if ratio == 1.0 {
            barsState = .hidden
        } else if ratio == 0 {
            barsState = .revealed
        }

        transitionProgress = ratio
        delegate?.setBarsVisibility(1.0 - ratio, animated: false, animationDuration: nil)
    }

    private func hiddenAndScrolling(in scrollView: UIScrollView) {
        let startedDraggingAtBottom = draggingStartPosY >= scrollView.contentOffsetYAtBottom
        if startedDraggingAtBottom, bottomRevealGestureState == .possible {
            let isInBottomBounceArea = scrollView.contentOffset.y > scrollView.contentOffsetYAtBottom
            if isInBottomBounceArea {
                revealBars(animated: true)
                bottomRevealGestureState = .triggered
            } else {
                // If user starts scrolling up, invalidate the possible reverse (scroll down) gesture
                bottomRevealGestureState = .cancelled
            }
        }

        guard scrollView.contentOffset.y < 0 else { return }

        transitionStartPosY = 0
        transitionStartProgress = transitionProgress
        barsState = .transitioning

        let ratio = calculateTransitionRatio(for: scrollView.contentOffset.y)
        delegate?.setBarsVisibility(1.0 - ratio, animated: false, animationDuration: nil)
        transitionProgress = ratio
    }

    private func calculateTransitionRatio(for contentOffset: CGFloat) -> CGFloat {
        let distance = contentOffset - transitionStartPosY
        let barsHeight = combinedBarsHeight

        guard barsHeight > 0 else { return 0 }

        guard delegate?.isFloatingChromeEnabled == true else {
            let cumulativeDistance = (barsHeight * transitionProgress) + distance
            let normalizedDistance = max(cumulativeDistance, 0)

            // We used to fix the scroll position in place as the transition happened
            //  but now the bars disappear too. This adjusts for that.
            return min(normalizedDistance / barsHeight * Metrics.legacyTransitionSpeed, 1.0)
        }

        // Stateless in the frame count: progress is a pure function of how far the current drag has
        // travelled from the fixed anchor `didStartScrolling` set, so it's correct after any number of
        // in-drag reversals without needing to re-anchor.
        let target = transitionStartProgress + distance / Metrics.floatingTransitionTravel
        return rateLimitedProgress(towards: target)
    }

    /// Clamps how fast a collapse may advance. Reveals are left uncapped — they are already gated by
    /// their own thresholds, and slowing them down would fight the finger.
    private func rateLimitedProgress(towards target: CGFloat) -> CGFloat {
        let now = currentTime()
        let elapsed = lastProgressTimestamp.map { now - $0 } ?? Metrics.nominalFrameDuration
        lastProgressTimestamp = now

        guard target > transitionProgress else { return min(max(target, 0), 1.0) }

        let timeStep = min(max(elapsed, 0), Metrics.maxRateLimitTimeStep)
        let maxStep = Metrics.maxCollapseProgressPerSecond * CGFloat(timeStep)
        return min(max(min(target, transitionProgress + maxStep), 0), 1.0)
    }

    func didFinishScrolling(in scrollView: UIScrollView, velocity: CGFloat) {
        defer {
            bottomRevealGestureState = .possible
        }

        guard bottomRevealGestureState != .triggered else {
            return
        }

        guard delegate?.isFloatingChromeEnabled == true else {
            guard velocity >= 0 else {
                revealBars(animated: true)
                return
            }

            let isAboveExtendedBottomBounceArea = scrollView.contentOffset.y < scrollView.contentOffsetYAtBottom - combinedBarsHeight
            guard barsState == .transitioning || isAboveExtendedBottomBounceArea else { return }

            guard velocity == 0 else {
                hideBars(animated: true)
                return
            }

            switch barsState {
            case .revealed, .hidden:
                break

            case .transitioning:
                if transitionProgress > 0.5 && transitionProgress < 1.0 {
                    hideBars(animated: true)
                } else if transitionProgress > 0 && transitionProgress  <= 0.5 {
                    revealBars(animated: true)
                }
            }
            return
        }

        // A real touch release is almost never exactly zero velocity, so gating the progress-based
        // decision on `velocity == 0` (as the legacy branch above does) means noise decides nearly every
        // slow, deliberate release. Below the commit threshold, settle by how far the transition actually
        // progressed instead — that's what makes a slow drag feel precise rather than arbitrary.
        let isFastFlick = abs(velocity) >= Metrics.floatingVelocityCommitThreshold
        if isFastFlick {
            if velocity < 0 {
                let duration = flickAnimationDuration(
                    base: delegate?.floatingMorphExpandDuration ?? 0.34,
                    fastest: Metrics.flickFastestExpandDuration,
                    velocity: velocity
                )
                revealBars(animated: true, animationDuration: duration)
            } else {
                let isAboveExtendedBottomBounceArea = scrollView.contentOffset.y < scrollView.contentOffsetYAtBottom - combinedBarsHeight
                if barsState == .transitioning || isAboveExtendedBottomBounceArea {
                    let duration = flickAnimationDuration(
                        base: delegate?.floatingMorphCollapseDuration ?? 0.20,
                        fastest: Metrics.flickFastestCollapseDuration,
                        velocity: velocity
                    )
                    hideBars(animated: true, animationDuration: duration)
                }
            }
            return
        }

        switch barsState {
        case .revealed, .hidden:
            break

        case .transitioning:
            if transitionProgress > 0.5 {
                hideBars(animated: true)
            } else {
                revealBars(animated: true)
            }
        }
    }

    func revealBars(animated: Bool, animationDuration: CGFloat? = nil) {
        let alreadyRevealed = barsState == .revealed

        barsState = .revealed
        transitionProgress = 0

        delegate?.setBarsVisibility(1, animated: animated && !alreadyRevealed, animationDuration: animationDuration)
    }

    func hideBars(animated: Bool, animationDuration: CGFloat? = nil) {
        guard barsState != .hidden else { return }

        barsState = .hidden
        transitionProgress = 1.0

        delegate?.setBarsVisibility(0, animated: animated, animationDuration: animationDuration)
    }

    /// Settle duration for a flick-triggered `revealBars`/`hideBars`, scaled by exit velocity so a
    /// firmer flick visibly finishes quicker. Continuous with `base` at `floatingVelocityCommitThreshold`
    /// (this is only ever called above that threshold, so there's no seam at the boundary with the
    /// deliberate-release branch, which always uses the unscaled default).
    private func flickAnimationDuration(base: CFTimeInterval, fastest: CFTimeInterval, velocity: CGFloat) -> CGFloat {
        let threshold = Metrics.floatingVelocityCommitThreshold
        let reference = Metrics.flickReferenceVelocity
        guard reference > threshold else { return CGFloat(fastest) }

        let speedFactor = ((abs(velocity) - threshold) / (reference - threshold)).clamped(to: 0...1)
        return CGFloat(base - (base - fastest) * Double(speedFactor))
    }
}

private extension UIScrollView {
    /// Calculate Y-axis content offset corresponding to very bottom of the scroll area
    var contentOffsetYAtBottom: CGFloat {
        let yOffset = contentSize.height - bounds.height
        return yOffset - adjustedContentInset.top + adjustedContentInset.bottom
    }
}
