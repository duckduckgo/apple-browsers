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

        /// Shortest collapse travel on a short page, so a few points of scroll don't snap the chrome.
        /// Rubber-banding past the page end makes up any shortfall.
        static let minimumShortPageTravel: CGFloat = 24

        /// Share of a short page's scroll range, with floating chrome hidden, that the collapse may use.
        /// The chrome finishes collapsing before the page end comes into view, as in Safari.
        static let floatingShortPageCollapseShare: CGFloat = 0.5
    }

    weak var delegate: BrowserChromeDelegate?

    private(set) var barsState: State = .revealed
    private var transitionProgress: CGFloat = 0.0

    var draggingStartPosY: CGFloat = 0

    var transitionStartPosY: CGFloat = 0

    private var transitionStartProgress: CGFloat = 0

    private var bottomRevealGestureState: BottomBounceRevealing = .possible

    /// Scroll range captured when the drag starts. Hiding the chrome shrinks the live range mid-drag, so
    /// travel derived from it would change under the user's finger.
    private var dragScrollableHeight: CGFloat = .greatestFiniteMagnitude

    /// How far the page scrolls with floating chrome hidden, measured when the drag starts.
    private var dragHiddenChromeScrollableHeight: CGFloat = .greatestFiniteMagnitude

    /// Whether the drag began at the page bottom, decided when it starts. Hiding the chrome hands the page
    /// more viewport, which moves the live bottom up past where a short page's drag began.
    private var draggingStartedAtBottom = false

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
        dragScrollableHeight = scrollView.scrollableHeight
        dragHiddenChromeScrollableHeight = hiddenChromeScrollableHeight(for: scrollView)
        draggingStartedAtBottom = draggingStartPosY >= scrollView.contentOffsetYAtBottom

        if delegate?.isFloatingChromeEnabled == true {
            // Capture rendered visibility first, then pin any in-flight morph so tracking
            // starts from that value without re-applying settled 0/1 chrome side effects.
            let currentBarsVisibility = delegate?.currentBarsVisibility ?? 1
            delegate?.pinFloatingChromeMorphIfNeeded()
            transitionProgress = 1 - currentBarsVisibility
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

    /// The offset is about to move without the finger moving. Shifting the drag's reference with it keeps
    /// the chrome's progress, which is measured from the offset, where it is.
    func contentOffsetWillShift(by delta: CGFloat) {
        draggingStartPosY += delta
        transitionStartPosY += delta
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
            if draggingStartedAtBottom, bottomRevealGestureState == .possible {
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

        // Page top is at `-adjustedContentInset.top` (not 0) when the scroll view has a top inset.
        let pageTopY = -scrollView.adjustedContentInset.top
        if draggingStartPosY <= pageTopY, scrollView.contentOffset.y <= pageTopY, barsState != .hidden {
            if barsState != .revealed || transitionProgress != 0 {
                barsState = .revealed
                transitionProgress = 0
                delegate?.setBarsVisibility(1, animated: true, animationDuration: nil)
            }
            transitionStartPosY = pageTopY
            transitionStartProgress = 0
            return
        }

        let ratio = calculateTransitionRatio(for: scrollView.contentOffset.y)
        let ratioMatchesSettledState =
            ((barsState == .hidden && ratio == 1) || (barsState == .revealed && ratio == 0))
            && transitionProgress == ratio
        guard !ratioMatchesSettledState else { return }

        if ratio >= 1.0 {
            barsState = .hidden
        } else if ratio <= 0.0 {
            barsState = .revealed
        } else {
            barsState = .transitioning
        }
        transitionProgress = ratio
        // Always a target, never a decision: the speed limit tracks an unhurried drag exactly and
        // paces out anything faster.
        delegate?.setBarsVisibility(1.0 - ratio, animated: true, animationDuration: nil)
    }

    private func revealedAndScrolling(in scrollView: UIScrollView) {
        guard scrollView.contentOffset.y > draggingStartPosY else { return }
        guard scrollView.contentOffset.y < scrollView.contentOffsetYAtBottom - bottomBounceMargin else { return }
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
        if draggingStartedAtBottom, bottomRevealGestureState == .possible {
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

    /// Scroll distance that takes the chrome from revealed to hidden. Floating chrome on a short page
    /// collapses within the first part of the range left once it hides, so the collapse is over before
    /// the page end shows, as in Safari. A classic-chrome page shorter than the standard travel collapses
    /// over its whole range, so it can still reach the hidden state.
    private var transitionTravel: CGFloat {
        guard delegate?.isFloatingChromeEnabled != true else {
            let shortPageTravel = dragHiddenChromeScrollableHeight * Metrics.floatingShortPageCollapseShare
            return min(Metrics.floatingTransitionTravel, max(shortPageTravel, Metrics.minimumShortPageTravel))
        }
        guard dragScrollableHeight < combinedBarsHeight else { return combinedBarsHeight }
        return min(combinedBarsHeight, max(dragScrollableHeight, Metrics.minimumShortPageTravel))
    }

    /// The scroll view keeps the insets of the chrome as it was when the drag started, so the hidden range
    /// is the current one less the space the chrome holds beyond its hidden insets.
    private func hiddenChromeScrollableHeight(for scrollView: UIScrollView) -> CGFloat {
        guard let delegate, delegate.isFloatingChromeEnabled else { return scrollView.scrollableHeight }
        let insets = scrollView.adjustedContentInset
        let hiddenInsets = delegate.floatingWebViewObscuredInsets(for: 0)
        let heldChromeHeight = max(0, (insets.top + insets.bottom) - (hiddenInsets.top + hiddenInsets.bottom))
        return scrollView.scrollableHeight - heldChromeHeight
    }

    /// Distance above the page bottom in which a drag starting with the chrome revealed doesn't hide it.
    /// Shrinks on pages too short to fit both it and the collapse travel, so they can still collapse.
    private var bottomBounceMargin: CGFloat {
        min(combinedBarsHeight, max(0, dragScrollableHeight - transitionTravel))
    }

    private func calculateTransitionRatio(for contentOffset: CGFloat) -> CGFloat {
        let distance = contentOffset - transitionStartPosY
        let travel = transitionTravel

        guard combinedBarsHeight > 0, travel > 0 else { return 0 }

        guard delegate?.isFloatingChromeEnabled == true else {
            let cumulativeDistance = (travel * transitionProgress) + distance
            let normalizedDistance = max(cumulativeDistance, 0)

            return min(normalizedDistance / travel * Metrics.legacyTransitionSpeed, 1.0)
        }

        let target = transitionStartProgress + distance / travel
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

        let isAboveExtendedBottomBounceArea = scrollView.contentOffset.y < scrollView.contentOffsetYAtBottom - bottomBounceMargin
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
                let isAboveExtendedBottomBounceArea = scrollView.contentOffset.y < scrollView.contentOffsetYAtBottom - bottomBounceMargin
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
        barsState = .revealed
        transitionProgress = 0

        delegate?.setBarsVisibility(1, animated: animated, animationDuration: animationDuration)
    }

    func hideBars(animated: Bool, animationDuration: CGFloat? = nil) {
        guard barsState != .hidden else { return }

        barsState = .hidden
        transitionProgress = 1.0

        delegate?.setBarsVisibility(0, animated: animated, animationDuration: animationDuration)
    }

}

private extension UIScrollView {
    /// Y-axis content offset at the very bottom of the scroll area. The top inset moves only the top of
    /// the range, so it plays no part here; floating chrome's top inset would otherwise put this short
    /// of the real bottom, and a drag from the top of a short page would count as starting at the bottom.
    var contentOffsetYAtBottom: CGFloat {
        contentSize.height - bounds.height + adjustedContentInset.bottom
    }

    /// Distance between the top and bottom of the scroll area.
    var scrollableHeight: CGFloat {
        contentOffsetYAtBottom + adjustedContentInset.top
    }
}
