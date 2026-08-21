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

        static let legacyTransitionSpeed: CGFloat = 0.5

        static let floatingVelocityCommitThreshold: CGFloat = 0.15
    }

    weak var delegate: BrowserChromeDelegate?

    private(set) var barsState: State = .revealed
    private var transitionProgress: CGFloat = 0.0

    var draggingStartPosY: CGFloat = 0

    var transitionStartPosY: CGFloat = 0

    private var transitionStartProgress: CGFloat = 0

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

    func didStartScrolling(in scrollView: UIScrollView) {
        draggingStartPosY = scrollView.contentOffset.y

        if delegate?.isFloatingChromeEnabled == true {
            transitionProgress = 1 - (delegate?.currentBarsVisibility ?? 1)
            if transitionProgress <= 0 {
                barsState = .revealed
            } else if transitionProgress >= 1 {
                barsState = .hidden
            } else {
                barsState = .transitioning
            }
            transitionStartPosY = scrollView.contentOffset.y
            transitionStartProgress = transitionProgress
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

        if draggingStartPosY <= 0, scrollView.contentOffset.y <= 0 {
            if barsState != .revealed || transitionProgress != 0 {
                barsState = .revealed
                transitionProgress = 0
                delegate?.setBarsVisibility(1, animated: false, animationDuration: nil)
            }
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
        return target.clamped(to: 0...1)
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
                revealBars(animated: true)
            } else {
                let isAboveExtendedBottomBounceArea = scrollView.contentOffset.y < scrollView.contentOffsetYAtBottom - combinedBarsHeight
                if barsState == .transitioning || isAboveExtendedBottomBounceArea {
                    hideBars(animated: true)
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

}

private extension UIScrollView {
    /// Calculate Y-axis content offset corresponding to very bottom of the scroll area
    var contentOffsetYAtBottom: CGFloat {
        let yOffset = contentSize.height - bounds.height
        return yOffset - adjustedContentInset.top + adjustedContentInset.bottom
    }
}
