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
        static let floatingTransitionTravel: CGFloat = 80

        static let maxCollapseProgressPerSecond: CGFloat = 7.0

        static let maxRateLimitTimeStep: CFTimeInterval = 1.0 / 30.0

        static let nominalFrameDuration: CFTimeInterval = 1.0 / 60.0

        static let legacyTransitionSpeed: CGFloat = 0.5

        static let floatingVelocityCommitThreshold: CGFloat = 0.15

        static let flickReferenceVelocity: CGFloat = 1.2

        static let flickFastestCollapseDuration: CFTimeInterval = 0.08
        static let flickFastestExpandDuration: CFTimeInterval = 0.14

        static let floatingSnapCommitDistance: CGFloat = 16
    }

    weak var delegate: BrowserChromeDelegate?

    private(set) var barsState: State = .revealed
    private var transitionProgress: CGFloat = 0.0

    var draggingStartPosY: CGFloat = 0

    var transitionStartPosY: CGFloat = 0

    private var transitionStartProgress: CGFloat = 0

    private var lastProgressTimestamp: CFTimeInterval?

    private enum SnapDirection {
        case collapsing
        case revealing
    }

    private var floatingCommittedDirection: SnapDirection?
    private var floatingCommitOffsetY: CGFloat?

    private let currentTime: () -> CFTimeInterval

    private var bottomRevealGestureState: BottomBounceRevealing = .possible

    #if DEBUG
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

    private func floatingDidScroll(in scrollView: UIScrollView) {
        if barsState == .hidden {
            let startedDraggingAtBottom = draggingStartPosY >= scrollView.contentOffsetYAtBottom
            if startedDraggingAtBottom, bottomRevealGestureState == .possible {
                if scrollView.contentOffset.y > scrollView.contentOffsetYAtBottom {
                    revealBars(animated: true)
                    bottomRevealGestureState = .triggered
                    return
                } else {
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

            return min(normalizedDistance / barsHeight * Metrics.legacyTransitionSpeed, 1.0)
        }

        let target = transitionStartProgress + distance / Metrics.floatingTransitionTravel
        return rateLimitedProgress(towards: target)
    }

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
            finishLegacyScrolling(in: scrollView, velocity: velocity)
            return
        }

        finishFloatingScrolling(in: scrollView, velocity: velocity)
    }

    private func finishLegacyScrolling(in scrollView: UIScrollView, velocity: CGFloat) {
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
    }

    private func finishFloatingScrolling(in scrollView: UIScrollView, velocity: CGFloat) {
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
