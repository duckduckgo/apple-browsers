//
//  PullToRefreshViewAdapter.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/**
 *
 * A custom implementation of pull-to-refresh functionality that works with any UIView.
 * This class creates a transparent background UIScrollView to display the native
 * UIRefreshControl while transforming a target view in response to pull gestures.
 *
 * ## How it works:
 * 1. A transparent "fake" scroll view is placed behind the target view to host the
 *    standard UIRefreshControl
 * 2. A pan gesture recognizer tracks vertical pulls on the content
 * 3. When pulled down, the target view moves with the gesture while the refresh
 *    control appears in the background
 * 4. When pulled past the threshold, a refresh is triggered
 *
 * This approach allows for pull-to-refresh functionality in contexts where a standard
 * UIScrollView implementation isn't possible or desirable, such as with WKWebViews.
 *
 */
final class PullToRefreshViewAdapter: NSObject {

    private enum Constant {

        // Base values for portrait orientation on standard devices
        static let refreshTriggerRatio: CGFloat = 0.3 // % of container height as float

        static let minimumTriggerThreshold: CGFloat = 80
        static let maximumFloatingUITriggerThreshold: CGFloat = 120
        static let refreshingPullDistance: CGFloat = 80
    }

    private var refreshTriggerThreshold: CGFloat {
        let containerHeight = pullableView?.bounds.height ?? UIScreen.main.bounds.height
        return Self.refreshTriggerThreshold(containerHeight: containerHeight,
                                            isFloatingUIEnabled: isFloatingUIEnabled)
    }

    static func refreshTriggerThreshold(containerHeight: CGFloat, isFloatingUIEnabled: Bool) -> CGFloat {
        let calculatedThreshold = containerHeight * Constant.refreshTriggerRatio
        let threshold = max(calculatedThreshold, Constant.minimumTriggerThreshold)
        return isFloatingUIEnabled ? min(threshold, Constant.maximumFloatingUITriggerThreshold) : threshold
    }

    private let backdropView = UIView()
    private let fakeScrollView = UIScrollView()
    private let refreshControl = UIRefreshControl()
    private var topConstraint: NSLayoutConstraint?
    private var panGestureRecognizer: UIPanGestureRecognizer?

    private var isPulling = false
    private var isRefreshControlEnabled = true
    private var isPullSuspended = false
    private var didTriggerRefresh = false
    private var didEndRefreshing = false
    private var initialTranslationY: CGFloat = 0
    private var didBeginGestureAtTop = false
    private var pullableViewClipsToBoundsBeforePull: Bool?
    private var pullableViewBackgroundColorBeforePull: UIColor?
    private var webViewBackgroundColorBeforePull: UIColor?
    private var refreshBackgroundColorDuringPull: UIColor?

    private weak var scrollView: UIScrollView?
    private weak var pullableView: UIView?
    private weak var webView: WKWebView?
    private let isFloatingUIEnabled: Bool
    private let onRefresh: () -> Void

    var backgroundColor: UIColor? {
        didSet {
            webViewBackgroundDidChange()
        }
    }

    private var isFloatingRefreshBackgroundActive: Bool {
        isFloatingUIEnabled && pullableViewClipsToBoundsBeforePull != nil
    }

    static func refreshBackgroundColor(pageBackgroundColor: UIColor?) -> UIColor {
        pageBackgroundColor ?? UIColor(designSystemColor: .background)
    }

    static func pullableViewRestingOffset(isRefreshing: Bool, isFloatingUIEnabled: Bool) -> CGFloat {
        isRefreshing && isFloatingUIEnabled ? Constant.refreshingPullDistance : 0
    }

    static func applyRefreshBackgroundColor(_ backgroundColor: UIColor, to webView: WKWebView) {
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        webView.underPageBackgroundColor = backgroundColor
    }

    func webViewBackgroundDidChange() {
        applyBackgroundColor()
        if isFloatingRefreshBackgroundActive {
            applyFloatingRefreshBackground()
        }
    }

    func webViewUnderPageBackgroundDidChange() {
        applyBackgroundColor()
    }

    private func determineRefreshControlTintColor(for backgroundColor: UIColor?) -> UIColor {
        guard let backgroundColor = backgroundColor else {
            return UIColor(designSystemColor: .iconsSecondary)
        }

        let userInterfaceStyle: UIUserInterfaceStyle = backgroundColor.brightnessPercentage < 50 ? .dark : .light
        return UIColor(designSystemColor: .iconsSecondary).resolvedColor(with: .init(userInterfaceStyle: userInterfaceStyle))
    }

    /**
     * Initializes the pull-to-refresh logic with the necessary components.
     *
     * @param scrollView The scroll view that will be monitored for scroll position.
     *                   This is typically the main content scroll view (e.g., a WKWebView's scrollView)
     *                   that will determine when pulling should begin.
     *
     * @param pullableView The view that will be transformed/moved during the pull gesture.
     *                     This is the main content container that visually responds to the pull.
     *
     * @param onRefresh A closure that will be called when a refresh is triggered.
     *                  Implement your data reloading logic in this closure.
     */
    init(with scrollView: UIScrollView,
         pullableView: UIView,
         webView: WKWebView? = nil,
         isFloatingUIEnabled: Bool,
         onRefresh: @escaping () -> Void) {
        self.scrollView = scrollView
        self.pullableView = pullableView
        self.webView = webView
        self.isFloatingUIEnabled = isFloatingUIEnabled
        self.onRefresh = onRefresh

        super.init()
        setupBackgroundScrollView(basedOn: pullableView)
        fakeScrollView.refreshControl = refreshControl
        setupPanGestureRecognizer()
        if isFloatingUIEnabled {
            applyBackgroundColor()
        } else {
            refreshControl.tintColor = UIColor(designSystemColor: .iconsSecondary)
        }
    }

    private func applyBackgroundColor() {
        let pageBackgroundColor = isFloatingUIEnabled
            ? refreshBackgroundColorDuringPull ?? webView?.underPageBackgroundColor
            : backgroundColor
        let refreshBackgroundColor = Self.refreshBackgroundColor(pageBackgroundColor: pageBackgroundColor)
        backdropView.backgroundColor = refreshBackgroundColor
        fakeScrollView.backgroundColor = .clear
        refreshControl.backgroundColor = isFloatingUIEnabled ? .clear : refreshBackgroundColor
        refreshControl.tintColor = determineRefreshControlTintColor(for: refreshBackgroundColor)

        if isFloatingUIEnabled, !isFloatingRefreshBackgroundActive {
            scrollView?.backgroundColor = refreshBackgroundColor
        }
    }

    private func setupBackgroundScrollView(basedOn view: UIView) {
        guard let superview = view.superview else { return }

        backdropView.translatesAutoresizingMaskIntoConstraints = false
        superview.insertSubview(backdropView, at: 0)

        // Set up the background scroll view that will be visible when pulling down
        fakeScrollView.backgroundColor = .clear
        fakeScrollView.translatesAutoresizingMaskIntoConstraints = false
        fakeScrollView.isScrollEnabled = true // Enable scrolling for refresh control
        fakeScrollView.clipsToBounds = false
        if isFloatingUIEnabled {
            fakeScrollView.isUserInteractionEnabled = false
            fakeScrollView.contentInsetAdjustmentBehavior = .never
            superview.insertSubview(fakeScrollView, aboveSubview: view)
        } else {
            superview.insertSubview(fakeScrollView, aboveSubview: backdropView)
        }

        let topConstraint = fakeScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        self.topConstraint = topConstraint

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: superview.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            topConstraint,
            fakeScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fakeScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fakeScrollView.bottomAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let fakeContentView = UIView()
        fakeContentView.translatesAutoresizingMaskIntoConstraints = false
        fakeScrollView.addSubview(fakeContentView)

        // Make the content view much taller than the scroll view to allow scrolling
        NSLayoutConstraint.activate([
            fakeContentView.topAnchor.constraint(equalTo: fakeScrollView.topAnchor),
            fakeContentView.leadingAnchor.constraint(equalTo: fakeScrollView.leadingAnchor),
            fakeContentView.trailingAnchor.constraint(equalTo: fakeScrollView.trailingAnchor),
            fakeContentView.widthAnchor.constraint(equalTo: fakeScrollView.widthAnchor),
            fakeContentView.bottomAnchor.constraint(equalTo: fakeScrollView.bottomAnchor),
            fakeContentView.heightAnchor.constraint(equalToConstant: 1500) // Tall enough to scroll
        ])
    }

    private func setupPanGestureRecognizer() {
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.delegate = self
        self.panGestureRecognizer = panGestureRecognizer
        scrollView?.addGestureRecognizer(panGestureRecognizer)
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialTranslationY = 0
            if let scrollView {
                didBeginGestureAtTop = isFloatingUIEnabled && isAtTop(scrollView)
            }
        case .changed:
            let translation = gesture.translation(in: pullableView)
            handleVerticalChange(translationY: translation.y)
        case .ended, .cancelled:
            let shouldKeepRefreshVisible = refreshControl.isRefreshing && !didEndRefreshing
            resetPullState()
            animatePullableViewToRestingPosition(whileRefreshing: shouldKeepRefreshVisible)
        default:
            break
        }
    }

    private func handleVerticalChange(translationY: CGFloat) {
        guard let scrollView else { return }

        let wasNotPulling = !isPulling
        startPullingIfAtTop(of: scrollView)
        if isPulling {
            if wasNotPulling {
                initialTranslationY = didBeginGestureAtTop ? 0 : translationY
            }
            let pullDistance = calculatePullDistance(translationY: translationY)
            handlePullEffect(pullDistance: pullDistance)
            triggerRefreshIfNeeded(pullDistance: pullDistance)
        }
    }

    private func startPullingIfAtTop(of scrollView: UIScrollView) {
        if isAtTop(scrollView) {
            if !isPulling, isFloatingUIEnabled, pullableViewClipsToBoundsBeforePull == nil {
                pullableViewClipsToBoundsBeforePull = pullableView?.clipsToBounds
                pullableView?.clipsToBounds = true
                pullableViewBackgroundColorBeforePull = pullableView?.backgroundColor
                if let webView {
                    webViewBackgroundColorBeforePull = webView.backgroundColor
                    refreshBackgroundColorDuringPull = Self.refreshBackgroundColor(
                        pageBackgroundColor: webView.underPageBackgroundColor
                    )
                }
                applyFloatingRefreshBackground()
            }
            scrollView.bounces = false
            isPulling = true
        }
    }

    private func isAtTop(_ scrollView: UIScrollView) -> Bool {
        isFloatingUIEnabled
            ? scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
            : scrollView.contentOffset.y < 0
    }

    private func calculatePullDistance(translationY: CGFloat) -> CGFloat {
        let adjustedTranslation = max(0, translationY - initialTranslationY)
        // Allow full movement up to the refresh trigger threshold
        if adjustedTranslation <= refreshTriggerThreshold {
            return adjustedTranslation
        } else {
            // Apply gradually increasing resistance beyond the refresh trigger threshold
            let extraPull = adjustedTranslation - refreshTriggerThreshold

            // Quadratic resistance curve - starts gentle but increases rapidly
            let resistanceFactor = 0.4 / (1 + 0.3 * pow(extraPull / refreshTriggerThreshold, 2))
            let resistedExtraPull = extraPull * resistanceFactor

            return refreshTriggerThreshold + resistedExtraPull
        }
    }

    private func handlePullEffect(pullDistance: CGFloat) {
        applyFloatingRefreshBackground()
        if isFloatingUIEnabled, let scrollView {
            scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
        }

        // Move the pullable view down based on pull distance
        pullableView?.transform = CGAffineTransform(translationX: 0, y: pullDistance)

        // Update the background scroll view's content offset to match the pull
        // We only adjust the content offset if not refreshing to avoid hiding the refresh spinner
        if !refreshControl.isRefreshing {
            fakeScrollView.contentOffset.y = -pullDistance * 0.5
        }
    }

    private func applyFloatingRefreshBackground() {
        guard isFloatingUIEnabled else { return }
        let refreshBackgroundColor = refreshBackgroundColorDuringPull
            ?? Self.refreshBackgroundColor(pageBackgroundColor: webView?.underPageBackgroundColor)
        backdropView.backgroundColor = refreshBackgroundColor
        refreshControl.backgroundColor = .clear
        refreshControl.tintColor = determineRefreshControlTintColor(for: refreshBackgroundColor)
        pullableView?.backgroundColor = refreshBackgroundColor
        scrollView?.backgroundColor = refreshBackgroundColor
        if let webView {
            Self.applyRefreshBackgroundColor(refreshBackgroundColor, to: webView)
        }
    }

    private func triggerRefreshIfNeeded(pullDistance: CGFloat) {
        // Trigger refresh if pulled past threshold and not already triggered
        if pullDistance > refreshTriggerThreshold, !didTriggerRefresh {
            beginRefreshing()
        }
    }

    private func resetPullState() {
        isPulling = false
        scrollView?.bounces = true
        didTriggerRefresh = false
        didBeginGestureAtTop = false
        if didEndRefreshing {
            refreshControl.endRefreshing()
            didEndRefreshing = false
        }
    }

    private func animatePullableViewToRestingPosition(whileRefreshing: Bool) {
        let restingOffset = Self.pullableViewRestingOffset(isRefreshing: whileRefreshing,
                                                           isFloatingUIEnabled: isFloatingUIEnabled)
        UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveEaseInOut) {
            self.pullableView?.transform = CGAffineTransform(translationX: 0, y: restingOffset)
            if !whileRefreshing {
                self.fakeScrollView.contentOffset.y = 0
            }
        } completion: { _ in
            if restingOffset == 0 {
                self.restorePullableViewClippingIfNeeded()
            }
        }
    }

    private func restorePullableViewClippingIfNeeded() {
        guard !isPulling, let pullableViewClipsToBoundsBeforePull else { return }
        pullableView?.clipsToBounds = pullableViewClipsToBoundsBeforePull
        pullableView?.backgroundColor = pullableViewBackgroundColorBeforePull
        pullableViewBackgroundColorBeforePull = nil
        webView?.backgroundColor = webViewBackgroundColorBeforePull
        webViewBackgroundColorBeforePull = nil
        webView?.underPageBackgroundColor = nil
        refreshBackgroundColorDuringPull = nil
        self.pullableViewClipsToBoundsBeforePull = nil
        applyBackgroundColor()
    }

    private func beginRefreshing() {
        didEndRefreshing = false
        refreshControl.beginRefreshing()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        didTriggerRefresh = true
        onRefresh()
    }

    /**
     * Ends the refreshing state and resets the UI.
     * Call this method when your data reload operation completes.
     */
    func endRefreshing() {
        didEndRefreshing = true
        if !isPulling {
            refreshControl.endRefreshing()
            animatePullableViewToRestingPosition(whileRefreshing: false)
        }
    }

    /**
     * Enables or disables the refresh control.
     * Use this to temporarily disable pull-to-refresh functionality.
     *
     * @param isEnabled Whether the refresh control should be enabled.
     */
    func setRefreshControlEnabled(_ isEnabled: Bool) {
        isRefreshControlEnabled = isEnabled
        applyRefreshControlState()
    }

    /// Suspends the pull gesture itself, not just the refresh control, and outranks
    /// `setRefreshControlEnabled` — the monitored scroll view can be reparented outside the tab
    /// (WebKit's fullscreen window), where a drag must not reach `onRefresh`.
    func setPullSuspended(_ isSuspended: Bool) {
        isPullSuspended = isSuspended
        panGestureRecognizer?.isEnabled = !isSuspended
        applyRefreshControlState()
    }

    private func applyRefreshControlState() {
        guard !isPulling else { return }

        let shouldAttach = isRefreshControlEnabled && !isPullSuspended
        fakeScrollView.refreshControl = shouldAttach ? refreshControl : nil
    }

    func setTopOffset(_ offset: CGFloat) {
        topConstraint?.constant = offset
    }

}

extension PullToRefreshViewAdapter: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

}
