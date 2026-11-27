//
//  BrowserChromeManager.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import WebKit

protocol BrowserChromeDelegate: AnyObject {
    
    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?)
    func resetBars(animated: Bool)
    func setNavigationBarHidden(_ hidden: Bool)
    func setRefreshControlEnabled(_ isEnabled: Bool)
    func setUnifiedInputContentOverlaySuppressed(_ suppressed: Bool)
    
    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?)
    
    var canHideBars: Bool { get }

    /// True = scroll must not move bars. Used when bar hides behind web keyboard.
    var isChromeScrollInteractionDisabled: Bool { get }

    var isToolbarHidden: Bool { get }
    var currentBarsVisibility: CGFloat { get }
    var toolbarHeight: CGFloat { get }
    /// True when the toolbar stays put while the rest of the chrome slides, as on iPad and in the minimal
    /// layout. Hiding the chrome then gives the page none of the toolbar's height.
    var isToolbarParked: Bool { get }
    var barsMaxHeight: CGFloat { get }
    var isInMinimalChromeLayout: Bool { get }

    var isFloatingChromeEnabled: Bool { get }

    /// Pins any in-flight floating chrome morph to its currently rendered visibility so scroll
    /// tracking can take over. No-op when not morphing; must not re-fire settled chrome side effects.
    func pinFloatingChromeMorphIfNeeded()

    /// Height (from the screen bottom) obscured by the visible bottom chrome at the given chrome
    /// visibility fraction, used to resize the floating web view so page-fixed footers pin to the top
    /// of whatever is on screen (toolbar -> capsule -> safe area).
    func floatingWebViewBottomObscuredHeight(for barsVisibilityPercent: CGFloat) -> CGFloat

    /// Chrome-obscured insets (measured from the full-bleed web view's edges) for the given chrome
    /// visibility, used to drive `WKWebView.obscuredContentInsets` on iOS 26.
    func floatingWebViewObscuredInsets(for barsVisibilityPercent: CGFloat) -> UIEdgeInsets

    func findInPageObscuredInsets(in webView: WKWebView) -> UIEdgeInsets?

    var floatingAIChatHeaderObscuredHeight: CGFloat { get }

    /// Height obscured at the top of the new tab page by the focused unified toggle input card, for page
    /// content that must sit below it (the contextual onboarding dialogs).
    var floatingNewTabPageTopObscuredHeight: CGFloat { get }

    var omniBar: any OmniBar { get }

    /// The view the address bar is drawn in: the floating toolbar's glass when the bar is embedded in it.
    var addressBarChromeView: UIView { get }
    var tabBarContainer: UIView { get }
}

extension BrowserChromeDelegate {

    var addressBarChromeView: UIView { omniBar.barView }

    func findInPageObscuredInsets(in webView: WKWebView) -> UIEdgeInsets? { nil }

    var floatingAIChatHeaderObscuredHeight: CGFloat { 0 }

    var isFloatingChromeEnabled: Bool { false }

    var currentBarsVisibility: CGFloat { isToolbarHidden ? 0 : 1 }

    func pinFloatingChromeMorphIfNeeded() {}
}

class BrowserChromeManager: NSObject, UIScrollViewDelegate {

    struct Constants {
        static let zoomThreshold: CGFloat = 0.1

        /// Pages that would scroll less than this with the chrome hidden keep their chrome.
        static let minimumScrollableHeight: CGFloat = 1
        
        static let contentSizeKVOKey = "contentSize"
    }

    weak var delegate: BrowserChromeDelegate? {
        didSet {
            animator.delegate = delegate
        }
    }

    var onUserScrolled: (() -> Void)?
    var onScrollStateChanged: (() -> Void)?

    private let animator = BarsAnimator()
    
    private var observation: NSKeyValueObservation?
    private weak var attachedScrollView: UIScrollView?

    private var startZoomScale: CGFloat = 0

    private var scrollToTop = true
    private var pendingFloatingScrollEndVelocity: CGFloat = 0
    /// Tracks an in-flight user drag/deceleration so passive WebKit scroll settling during page load
    /// does not drive floating chrome morph updates.
    private var isFloatingUserScrollActive = false
    /// The offset `followFloatingChromeBottom` last pinned the page to, while it follows a hiding bar.
    private var followedFloatingChromeBottomY: CGFloat?

    func attach(to scrollView: UIScrollView) {
        detach()
        
        attachedScrollView = scrollView
        scrollView.delegate = self
        
        observation = scrollView.observe(\.contentSize, options: .new) { [weak self] scrollView, observation in
            guard observation.newValue != observation.oldValue else { return }
            self?.scrollViewDidResizeContent(scrollView)
        }
    }
    
    func detach() {
        if delegate?.isFloatingChromeEnabled == true, attachedScrollView?.delegate === self {
            attachedScrollView?.delegate = nil
        }
        attachedScrollView = nil
        observation?.invalidate()
        observation = nil
        pendingFloatingScrollEndVelocity = 0
        isFloatingUserScrollActive = false
        followedFloatingChromeBottomY = nil
    }
    
    private func scrollViewDidResizeContent(_ scrollView: UIScrollView) {
        guard shouldHandleScrollView(scrollView) else { return }
        guard delegate?.isChromeScrollInteractionDisabled != true else { return }
        if !canHideBars(for: scrollView) && animator.barsState != .revealed {
            animator.revealBars(animated: false)
        }
    }
        
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard shouldHandleScrollView(scrollView) else { return }
        if delegate?.isFloatingChromeEnabled == true {
            onScrollStateChanged?()
        }
        guard !scrollView.isZooming else { return }

        let isFloatingDeceleration = delegate?.isFloatingChromeEnabled == true
            && scrollView.isDecelerating
            && isFloatingUserScrollActive
        guard scrollView.isDragging || isFloatingDeceleration else { return }
        if scrollView.isDragging {
            onUserScrolled?()
        }

        // Bar hidden behind web keyboard. Do not touch bars, else page jerks.
        guard delegate?.isChromeScrollInteractionDisabled != true else { return }

        guard canHideBars(for: scrollView) else {
            if animator.barsState != .revealed {
                animator.revealBars(animated: false)
            }
            return
        }

        if let delegate, delegate.isFloatingChromeEnabled {
            // A drag past the bottom mid-hide would otherwise show for a frame before the bar pulls it back.
            let visibility = delegate.currentBarsVisibility
            if visibility > 0, visibility < 1 {
                followFloatingChromeBottom { delegate.floatingWebViewObscuredInsets(for: visibility).bottom }
            }
        }
        animator.didScroll(in: scrollView)
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard shouldHandleScrollView(scrollView) else { return }
        guard scrollView.isTracking else { return }
        guard !scrollView.isZoomBouncing else { return }
        guard delegate?.isChromeScrollInteractionDisabled != true else { return }
        
        if scrollView.fullyZoomedOut {
            animator.revealBars(animated: true)
        } else if abs(scrollView.zoomScale - startZoomScale) > Constants.zoomThreshold, delegate?.canHideBars ?? true {
            animator.hideBars(animated: true)
        }
    }
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        guard shouldHandleScrollView(scrollView) else { return }
        startZoomScale = scrollView.zoomScale
        delegate?.setRefreshControlEnabled(false)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard shouldHandleScrollView(scrollView) else { return }
        delegate?.setRefreshControlEnabled(true)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard shouldHandleScrollView(scrollView) else { return }
        guard !scrollView.isZooming else { return }

        pendingFloatingScrollEndVelocity = 0
        isFloatingUserScrollActive = true
        animator.didStartScrolling(in: scrollView)
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard shouldHandleScrollView(scrollView) else { return }
        guard !scrollView.isZooming else { return }
        guard delegate?.isChromeScrollInteractionDisabled != true else { return }
        guard canHideBars(for: scrollView) else { return }

        guard delegate?.isFloatingChromeEnabled == true else {
            animator.didFinishScrolling(in: scrollView, velocity: velocity.y)
            return
        }
        pendingFloatingScrollEndVelocity = velocity.y
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard shouldHandleScrollView(scrollView) else { return }
        if !decelerate {
            isFloatingUserScrollActive = false
        }
        guard delegate?.isFloatingChromeEnabled == true, !decelerate else { return }
        finishFloatingScrolling(in: scrollView)
        // UIKit can still report dragging/tracking inside didEndDragging. Retry after it clears them.
        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self, let scrollView, scrollView === self.attachedScrollView,
                  self.delegate?.isFloatingChromeEnabled == true,
                  !self.isFloatingUserScrollActive else { return }
            self.onScrollStateChanged?()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard shouldHandleScrollView(scrollView) else { return }
        isFloatingUserScrollActive = false
        guard delegate?.isFloatingChromeEnabled == true else { return }
        onScrollStateChanged?()
        finishFloatingScrolling(in: scrollView)
    }

    private func shouldHandleScrollView(_ scrollView: UIScrollView) -> Bool {
        delegate?.isFloatingChromeEnabled != true || scrollView === attachedScrollView
    }

    private func finishFloatingScrolling(in scrollView: UIScrollView) {
        guard delegate?.isFloatingChromeEnabled == true, scrollView === attachedScrollView else { return }
        defer {
            pendingFloatingScrollEndVelocity = 0
        }
        guard !scrollView.isZooming else { return }
        guard delegate?.isChromeScrollInteractionDisabled != true else { return }
        guard canHideBars(for: scrollView) else { return }

        animator.didFinishScrolling(in: scrollView, velocity: pendingFloatingScrollEndVelocity)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        guard shouldHandleScrollView(scrollView) else { return true }
        defer {
            scrollToTop = true
        }

        switch animator.barsState {
        case .hidden:
            animator.revealBars(animated: true)
            return false
        case .transitioning:
            return false
        default:
            return scrollToTop
        }
    }

    func preventNextScrollToTop() {
        scrollToTop = false
    }

    /// Bars hide only on a page taller than the viewport they leave behind, so the page still scrolls
    /// with them gone. A page that would fit once they hide keeps them: no collapse even starts.
    private func canHideBars(for scrollView: UIScrollView) -> Bool {
        guard delegate?.canHideBars ?? true else { return false }
        // Chrome can't hold more than the scroll view's insets, so a page that scrolls past them is long
        // enough without asking the delegate, whose inset lookup is too slow for every scroll event.
        let scrollableHeightWithoutInsets = scrollView.contentSize.height - scrollView.bounds.height
        if delegate?.isFloatingChromeEnabled == true, scrollableHeightWithoutInsets >= Constants.minimumScrollableHeight {
            return true
        }
        return hiddenChromeScrollableHeight(for: scrollView) >= Constants.minimumScrollableHeight
    }

    /// How far the page would scroll with the chrome fully hidden. Hiding hands the chrome's space to the
    /// page, so the space the chrome still holds comes off the current range.
    private func hiddenChromeScrollableHeight(for scrollView: UIScrollView) -> CGFloat {
        let insets = scrollView.adjustedContentInset
        let currentScrollableHeight = scrollView.contentSize.height + insets.top + insets.bottom - scrollView.bounds.height
        guard let delegate else { return currentScrollableHeight }

        let heldChromeHeight: CGFloat
        if delegate.isFloatingChromeEnabled {
            // Floating chrome changes the scroll view's insets only once a transition ends, so measure
            // what the insets on the scroll view hold, not what the visibility says they will.
            let hiddenInsets = delegate.floatingWebViewObscuredInsets(for: 0)
            heldChromeHeight = max(0, (insets.top + insets.bottom) - (hiddenInsets.top + hiddenInsets.bottom))
        } else {
            let visibility = delegate.currentBarsVisibility.clamped(to: 0...1)
            heldChromeHeight = legacySlidingChromeHeight(for: delegate) * visibility
        }
        return currentScrollableHeight - heldChromeHeight
    }

    /// Classic chrome slides the toolbar, the omnibar and any tabs bar out together, and the page gets
    /// all of that space back. `barsMaxHeight` counts only the taller bar. A parked toolbar doesn't
    /// slide, so its height stays out.
    private func legacySlidingChromeHeight(for delegate: BrowserChromeDelegate) -> CGFloat {
        let tabsBarHeight = delegate.tabBarContainer.isHidden ? 0 : delegate.tabBarContainer.frame.height
        let toolbarHeight = delegate.isToolbarParked ? 0 : delegate.toolbarHeight
        let slidingHeight = toolbarHeight + delegate.omniBar.barView.expectedHeight + tabsBarHeight
        return max(delegate.barsMaxHeight, slidingHeight)
    }

    func reset(animated: Bool = true) {
        animator.revealBars(animated: animated)
    }

    /// Floating chrome holds the scroll view's insets until a hide ends, and WebKit then clamps the
    /// offset into the smaller range in a single frame. At the page bottom, keep the offset inside the
    /// range the hiding bar leaves, so the page follows the bar down instead of jumping once it settles.
    /// If the collapse reverses, the page follows the bar back up so it doesn't cover the last line.
    /// `obscuredBottom` is only read at the page end or while following, as the inset lookup is slow.
    func followFloatingChromeBottom(obscuredBottom: () -> CGFloat) {
        guard delegate?.isFloatingChromeEnabled == true,
              let scrollView = attachedScrollView,
              !scrollView.isZooming else { return }
        let contentEndY = scrollView.contentSize.height - scrollView.bounds.height
        guard followedFloatingChromeBottomY != nil || scrollView.contentOffset.y > contentEndY else { return }

        let obscuredBottom = min(obscuredBottom(), scrollView.contentInset.bottom)
        let pageTopY = -scrollView.adjustedContentInset.top
        let bottomY = max(pageTopY, contentEndY + obscuredBottom)
        let shift = bottomY - scrollView.contentOffset.y

        if let followedY = followedFloatingChromeBottomY, abs(scrollView.contentOffset.y - followedY) < 0.5 {
            // The page is still where following left it, so it tracks the bar in either direction.
            if obscuredBottom >= scrollView.contentInset.bottom {
                followedFloatingChromeBottomY = nil
            }
        } else if shift < 0, obscuredBottom < scrollView.contentInset.bottom {
            // Past the bottom the hiding bar leaves.
        } else {
            // Above that bottom, or the chrome is revealed: the user's offset stands.
            followedFloatingChromeBottomY = nil
            return
        }
        if obscuredBottom < scrollView.contentInset.bottom {
            followedFloatingChromeBottomY = bottomY
        }
        guard shift != 0 else { return }

        // The page moves under the finger, so the drag's reference moves with it and the bars keep
        // their progress.
        animator.contentOffsetWillShift(by: shift)
        scrollView.contentOffset.y = bottomY
    }
}

private extension UIScrollView {
    var fullyZoomedOut: Bool {
        return zoomScale <= minimumZoomScale
    }
}

extension Notification.Name {
    static let browserChromeVisibilityChanged = Notification.Name("com.duckduckgo.browserChrome.visibilityChanged")
}
